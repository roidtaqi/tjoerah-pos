<?php

namespace App\Domains\Inventory\Controllers;

use App\Http\Controllers\Controller;
use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\Wastage;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Services\InventoryService;
use App\Domains\POS\Models\Order;
use App\Domains\Reporting\Models\SystemAlert;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class WastageController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'warehouse_id' => 'required|integer|exists:warehouses,id',
            'inventory_item_id' => 'required|integer|exists:inventory_items,id',
            'quantity' => 'required|numeric|min:0.0001',
            'waste_type' => 'nullable|string|max:50',
            'reason' => 'nullable|string',
        ]);

        $item = InventoryItem::findOrFail($validated['inventory_item_id']);
        $warehouse = Warehouse::findOrFail($validated['warehouse_id']);
        $unitCost = (float) $item->weighted_average_cost;
        $value = $validated['quantity'] * $unitCost;

        return DB::transaction(function () use ($validated, $unitCost, $value, $request) {
            $wastage = Wastage::create([
                'outlet_id' => $validated['outlet_id'],
                'inventory_item_id' => $validated['inventory_item_id'],
                'user_id' => $request->user()?->id,
                'waste_type' => $validated['waste_type'] ?? 'spoilage',
                'quantity' => $validated['quantity'],
                'value' => $value,
                'reason' => $validated['reason'] ?? null,
            ]);

            // Negative stock movement for waste
            InventoryService::recordMovement(
                itemId: $validated['inventory_item_id'],
                warehouseId: $validated['warehouse_id'],
                quantity: -$validated['quantity'],
                type: 'waste',
                unitCost: $unitCost,
                referenceType: Wastage::class,
                referenceId: $wastage->id,
                reason: $validated['reason'] ?? null,
                userId: $request->user()?->id
            );

            // Check if daily waste exceeds 3% of daily revenue
            $today = now()->startOfDay();
            $dailyRevenue = (float) Order::where('outlet_id', $validated['outlet_id'])
                ->where('created_at', '>=', $today)
                ->sum('total');

            $dailyWaste = (float) Wastage::where('outlet_id', $validated['outlet_id'])
                ->where('created_at', '>=', $today)
                ->sum('value');

            if ($dailyRevenue > 0) {
                $percentage = ($dailyWaste / $dailyRevenue) * 100;
                if ($percentage > 3.0) {
                    SystemAlert::create([
                        'company_id' => $request->user()?->company_id,
                        'outlet_id' => $validated['outlet_id'],
                        'alert_type' => 'excessive_waste',
                        'severity' => 'warning',
                        'title' => 'Excessive Spoilage Alert',
                        'message' => 'Daily waste has reached Rp ' . number_format($dailyWaste) . ' which is ' . number_format($percentage, 2) . '% of daily revenue.',
                        'context' => [
                            'daily_revenue' => $dailyRevenue,
                            'daily_waste' => $dailyWaste,
                            'percentage' => $percentage,
                        ]
                    ]);
                }
            }

            return response()->json($wastage, 201);
        });
    }
}
