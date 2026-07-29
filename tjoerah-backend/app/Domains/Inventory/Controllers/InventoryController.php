<?php

namespace App\Domains\Inventory\Controllers;

use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\StockAdjustment;
use App\Domains\Inventory\Models\StockMovement;
use App\Domains\Inventory\Models\StockOpname;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Services\InventoryService;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class InventoryController extends Controller
{
    public function index(Request $request)
    {
        return InventoryItem::when(
            $request->user()?->company_id,
            fn ($query, $companyId) => $query->where('company_id', $companyId),
            fn ($query) => $query->when(
                $request->integer('company_id'),
                fn ($query, $companyId) => $query->where('company_id', $companyId),
            ),
        )
            ->when($request->string('item_type')->isNotEmpty(), fn ($query) => $query->where('item_type', request('item_type')))
            ->select('inventory_items.*')
            ->selectSub(function ($query) {
                $query->selectRaw('COALESCE(SUM(quantity), 0)')
                    ->from('stock_movements')
                    ->whereColumn('stock_movements.inventory_item_id', 'inventory_items.id');
            }, 'current_stock')
            ->paginate(100);
    }

    public function storeItem(Request $request)
    {
        $this->normalizeNullableItemFields($request);
        $validated = $request->validate($this->itemRules($request));
        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }
        $item = InventoryItem::create($validated);

        return response()->json($item, 201);
    }

    public function updateItem(Request $request, InventoryItem $inventoryItem)
    {
        $this->ensureItemIsAccessible($request, $inventoryItem);
        $this->normalizeNullableItemFields($request);
        $validated = $request->validate(
            $this->itemRules($request, $inventoryItem),
        );
        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }
        $inventoryItem->update($validated);

        return response()->json($inventoryItem->fresh());
    }

    public function warehouses(Request $request)
    {
        return Warehouse::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->paginate(50);
    }

    public function storeWarehouse(Request $request)
    {
        $warehouse = Warehouse::create($request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'name' => 'required|string|max:255',
            'type' => 'nullable|string|max:100',
            'is_active' => 'boolean',
        ]));

        return response()->json($warehouse, 201);
    }

    public function movements(Request $request)
    {
        return StockMovement::with(['inventoryItem', 'warehouse'])
            ->when($request->integer('warehouse_id'), fn ($query, $warehouseId) => $query->where('warehouse_id', $warehouseId))
            ->when($request->integer('inventory_item_id'), fn ($query, $itemId) => $query->where('inventory_item_id', $itemId))
            ->latest()
            ->paginate(100);
    }

    public function adjustment(Request $request)
    {
        $validated = $request->validate([
            'warehouse_id' => 'required|integer|exists:warehouses,id',
            'inventory_item_id' => 'required|integer|exists:inventory_items,id',
            'quantity' => 'required|numeric',
            'reason' => 'nullable|string',
        ]);

        $adjustment = StockAdjustment::create([
            ...$validated,
            'user_id' => $request->user()?->id,
            'status' => 'approved',
        ]);

        InventoryService::recordMovement(
            itemId: $validated['inventory_item_id'],
            warehouseId: $validated['warehouse_id'],
            quantity: (float) $validated['quantity'],
            type: 'adjustment',
            unitCost: 0.0,
            referenceType: StockAdjustment::class,
            referenceId: $adjustment->id,
            userId: $request->user()?->id
        );

        return response()->json($adjustment, 201);
    }

    public function opname(Request $request)
    {
        $opname = StockOpname::create([
            ...$request->validate([
                'warehouse_id' => 'required|integer|exists:warehouses,id',
                'opname_number' => 'nullable|string|max:100',
                'items' => 'nullable|array',
                'status' => 'nullable|string|max:50',
            ]),
            'user_id' => $request->user()?->id,
        ]);

        return response()->json($opname, 201);
    }

    public function transfer(Request $request)
    {
        $validated = $request->validate([
            'from_warehouse_id' => 'required|integer|exists:warehouses,id',
            'to_warehouse_id' => 'required|integer|exists:warehouses,id|different:from_warehouse_id',
            'inventory_item_id' => 'required|integer|exists:inventory_items,id',
            'quantity' => 'required|numeric|min:0',
            'reason' => 'nullable|string',
        ]);

        $out = InventoryService::recordMovement(
            itemId: $validated['inventory_item_id'],
            warehouseId: $validated['from_warehouse_id'],
            quantity: -1 * abs((float) $validated['quantity']),
            type: 'transfer_out',
            reason: $validated['reason'] ?? null,
            userId: $request->user()?->id
        );

        $in = InventoryService::recordMovement(
            itemId: $validated['inventory_item_id'],
            warehouseId: $validated['to_warehouse_id'],
            quantity: abs((float) $validated['quantity']),
            type: 'transfer_in',
            referenceType: StockMovement::class,
            referenceId: $out->id,
            reason: $validated['reason'] ?? null,
            userId: $request->user()?->id
        );

        return response()->json(['out' => $out, 'in' => $in], 201);
    }

    private function itemRules(
        Request $request,
        ?InventoryItem $inventoryItem = null,
    ): array {
        $presence = $inventoryItem ? 'sometimes' : 'required';
        $companyId = $request->user()?->company_id
            ?? $request->integer('company_id');

        return [
            'company_id' => 'nullable|integer|exists:companies,id',
            'name' => [$presence, 'string', 'max:255'],
            'sku' => [
                'nullable',
                'string',
                'max:100',
                Rule::unique('inventory_items', 'sku')
                    ->where(fn ($query) => $query->where('company_id', $companyId))
                    ->ignore($inventoryItem),
            ],
            'item_type' => [
                'nullable',
                Rule::in([
                    'raw_material',
                    'semi_finished',
                    'packaging',
                    'other',
                ]),
            ],
            'unit' => [$presence, 'string', 'max:50'],
            'weighted_average_cost' => 'nullable|numeric|min:0',
            'minimum_stock' => 'nullable|numeric|min:0',
            'is_active' => 'boolean',
        ];
    }

    private function ensureItemIsAccessible(
        Request $request,
        InventoryItem $inventoryItem,
    ): void {
        $companyId = $request->user()?->company_id;
        abort_if(
            $companyId
                && (int) $inventoryItem->company_id !== (int) $companyId,
            404,
        );
    }

    private function normalizeNullableItemFields(Request $request): void
    {
        foreach (['company_id', 'sku'] as $field) {
            if (
                $request->exists($field)
                && trim((string) $request->input($field)) === ''
            ) {
                $request->merge([$field => null]);
            }
        }
    }
}
