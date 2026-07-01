<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\InventoryItem;
use App\Models\StockAdjustment;
use App\Models\StockMovement;
use App\Models\StockOpname;
use App\Models\Warehouse;
use Illuminate\Http\Request;

class InventoryController extends Controller
{
    public function index(Request $request)
    {
        return InventoryItem::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->string('item_type')->isNotEmpty(), fn ($query) => $query->where('item_type', request('item_type')))
            ->paginate(100);
    }

    public function storeItem(Request $request)
    {
        $item = InventoryItem::create($request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'name' => 'required|string|max:255',
            'sku' => 'nullable|string|max:100',
            'item_type' => 'nullable|string|max:100',
            'unit' => 'nullable|string|max:50',
            'weighted_average_cost' => 'nullable|numeric',
            'minimum_stock' => 'nullable|numeric',
            'is_active' => 'boolean',
        ]));

        return response()->json($item, 201);
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

        StockMovement::create([
            ...$validated,
            'user_id' => $request->user()?->id,
            'movement_type' => 'adjustment',
            'reference_type' => StockAdjustment::class,
            'reference_id' => $adjustment->id,
        ]);

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

        $out = StockMovement::create([
            'warehouse_id' => $validated['from_warehouse_id'],
            'inventory_item_id' => $validated['inventory_item_id'],
            'quantity' => -1 * abs($validated['quantity']),
            'movement_type' => 'transfer_out',
            'reason' => $validated['reason'] ?? null,
            'user_id' => $request->user()?->id,
        ]);

        $in = StockMovement::create([
            'warehouse_id' => $validated['to_warehouse_id'],
            'inventory_item_id' => $validated['inventory_item_id'],
            'quantity' => abs($validated['quantity']),
            'movement_type' => 'transfer_in',
            'reference_type' => StockMovement::class,
            'reference_id' => $out->id,
            'reason' => $validated['reason'] ?? null,
            'user_id' => $request->user()?->id,
        ]);

        return response()->json(['out' => $out, 'in' => $in], 201);
    }
}
