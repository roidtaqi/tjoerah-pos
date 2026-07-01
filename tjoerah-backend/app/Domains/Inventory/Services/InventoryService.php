<?php

namespace App\Domains\Inventory\Services;

use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\StockMovement;
use App\Domains\Recipe\Services\RecipeService;
use Illuminate\Support\Facades\DB;

class InventoryService
{
    /**
     * Record a stock movement and recalculate quantities.
     */
    public static function recordMovement(
        int $itemId,
        int $warehouseId,
        float $quantity,
        string $type,
        float $unitCost = 0,
        ?string $referenceType = null,
        string|int|null $referenceId = null,
        ?string $referenceNumber = null,
        ?string $reason = null,
        ?int $userId = null
    ): StockMovement {
        return DB::transaction(function () use (
            $itemId, $warehouseId, $quantity, $type, $unitCost,
            $referenceType, $referenceId, $referenceNumber, $reason, $userId
        ) {
            // Get the latest movement to find the running total
            $latestMovement = StockMovement::where('inventory_item_id', $itemId)
                ->where('warehouse_id', $warehouseId)
                ->orderBy('created_at', 'desc')
                ->orderBy('id', 'desc')
                ->first();

            $before = $latestMovement ? (float) $latestMovement->after_quantity : 0.0;
            $after = $before + $quantity;

            $movement = StockMovement::create([
                'inventory_item_id' => $itemId,
                'warehouse_id' => $warehouseId,
                'user_id' => $userId,
                'movement_type' => $type,
                'quantity' => $quantity,
                'before_quantity' => $before,
                'after_quantity' => $after,
                'unit_cost' => $unitCost,
                'reference_type' => $referenceType,
                'reference_id' => $referenceId,
                'reference_number' => $referenceNumber,
                'reason' => $reason,
            ]);

            // If it's a stock in, update the Weighted Average Cost of the InventoryItem
            if ($type === 'stock_in' && $quantity > 0) {
                self::recalculateAverageCost($itemId, $quantity, $unitCost);
            }

            return $movement;
        });
    }

    /**
     * Recalculate Weighted Average Cost.
     */
    private static function recalculateAverageCost(int $itemId, float $newQty, float $newUnitCost): void
    {
        $item = InventoryItem::lockForUpdate()->find($itemId);
        if (!$item) {
            return;
        }

        // Sum current stock across all warehouses *before* this new transaction is fully computed
        // But since the StockMovement is already saved, the current sum of quantity includes $newQty.
        $totalStock = (float) StockMovement::where('inventory_item_id', $itemId)->sum('quantity');
        $stockBefore = max(0.0, $totalStock - $newQty);

        $currentVal = $stockBefore * (float) $item->weighted_average_cost;
        $newVal = $newQty * $newUnitCost;
        $totalVal = $currentVal + $newVal;
        $totalQty = $stockBefore + $newQty;

        $newAverageCost = $totalQty > 0 ? $totalVal / $totalQty : $newUnitCost;

        $item->update([
            'weighted_average_cost' => $newAverageCost
        ]);

        // Propagate cost updates to all active recipes using this item
        RecipeService::recalculateRecipeCostsUsingItem($itemId);
    }
}
