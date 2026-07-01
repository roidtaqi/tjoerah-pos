<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\GoodsReceipt;
use App\Models\PurchaseOrder;
use App\Models\StockMovement;
use App\Models\Supplier;
use Illuminate\Http\Request;

class PurchaseController extends Controller
{
    public function suppliers(Request $request)
    {
        return Supplier::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->paginate(100);
    }

    public function storeSupplier(Request $request)
    {
        $supplier = Supplier::create($request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'address' => 'nullable|string',
            'is_active' => 'boolean',
        ]));

        return response()->json($supplier, 201);
    }

    public function purchaseOrders(Request $request)
    {
        return PurchaseOrder::with('items')
            ->when($request->integer('supplier_id'), fn ($query, $supplierId) => $query->where('supplier_id', $supplierId))
            ->latest()
            ->paginate(100);
    }

    public function storePurchaseOrder(Request $request)
    {
        $validated = $request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'supplier_id' => 'required|integer|exists:suppliers,id',
            'warehouse_id' => 'nullable|integer|exists:warehouses,id',
            'po_number' => 'required|string|max:100|unique:purchase_orders,po_number',
            'status' => 'nullable|string|max:50',
            'ordered_at' => 'nullable|date',
            'expected_at' => 'nullable|date',
            'items' => 'nullable|array',
            'items.*.inventory_item_id' => 'required_with:items|integer|exists:inventory_items,id',
            'items.*.quantity' => 'required_with:items|numeric|min:0',
            'items.*.unit_cost' => 'required_with:items|numeric|min:0',
        ]);

        $po = PurchaseOrder::create([
            ...collect($validated)->except('items')->all(),
            'total' => collect($validated['items'] ?? [])->sum(fn ($item) => $item['quantity'] * $item['unit_cost']),
        ]);

        foreach ($validated['items'] ?? [] as $item) {
            $po->items()->create([
                ...$item,
                'total' => $item['quantity'] * $item['unit_cost'],
            ]);
        }

        return response()->json($po->load('items'), 201);
    }

    public function storeGoodsReceipt(Request $request)
    {
        $validated = $request->validate([
            'purchase_order_id' => 'nullable|integer|exists:purchase_orders,id',
            'warehouse_id' => 'required|integer|exists:warehouses,id',
            'receipt_number' => 'required|string|max:100|unique:goods_receipts,receipt_number',
            'items' => 'nullable|array',
            'items.*.inventory_item_id' => 'required_with:items|integer|exists:inventory_items,id',
            'items.*.quantity' => 'required_with:items|numeric|min:0',
            'items.*.unit_cost' => 'nullable|numeric|min:0',
            'invoice_attachment' => 'nullable|string|max:255',
            'received_at' => 'nullable|date',
        ]);

        $receipt = GoodsReceipt::create([
            ...$validated,
            'user_id' => $request->user()?->id,
            'received_at' => $validated['received_at'] ?? now(),
        ]);

        foreach ($validated['items'] ?? [] as $item) {
            StockMovement::create([
                'inventory_item_id' => $item['inventory_item_id'],
                'warehouse_id' => $validated['warehouse_id'],
                'user_id' => $request->user()?->id,
                'movement_type' => 'stock_in',
                'quantity' => $item['quantity'],
                'unit_cost' => $item['unit_cost'] ?? 0,
                'reference_type' => GoodsReceipt::class,
                'reference_id' => $receipt->id,
                'reference_number' => $receipt->receipt_number,
            ]);
        }

        return response()->json($receipt, 201);
    }
}
