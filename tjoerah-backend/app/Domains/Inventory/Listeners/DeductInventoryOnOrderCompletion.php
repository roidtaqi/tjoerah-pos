<?php

namespace App\Domains\Inventory\Listeners;

use App\Domains\Sales\Events\OrderCompleted;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Services\InventoryService;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeItem;
use App\Domains\Recipe\Models\RecipeVersion;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Log;

class DeductInventoryOnOrderCompletion implements ShouldQueue
{
    /**
     * Handle the event.
     */
    public function handle(OrderCompleted $event): void
    {
        $order = $event->order;

        // 1. Get the primary active warehouse for this order's outlet
        $warehouse = Warehouse::where('outlet_id', $order->outlet_id)
            ->where('is_active', true)
            ->first();

        if (!$warehouse) {
            Log::warning("No active warehouse found for outlet ID: {$order->outlet_id}. Skipping inventory deduction.");
            return;
        }

        // 2. Loop over order items to find recipes and deduct raw materials
        foreach ($order->items as $orderItem) {
            $recipe = Recipe::where('product_id', $orderItem->product_id)->first();
            if (!$recipe) {
                continue; // No recipe defined for this product
            }

            // Find active version
            $version = RecipeVersion::where('recipe_id', $recipe->id)
                ->where('version', $recipe->active_version)
                ->first();

            if (!$version) {
                continue; // No active version found
            }

            // Get all items in this recipe version
            $recipeItems = RecipeItem::where('recipe_version_id', $version->id)->get();
            $cogsTotal = 0.0;

            foreach ($recipeItems as $recipeItem) {
                if ($recipeItem->inventory_item_id) {
                    $qtyDeducted = (float) $recipeItem->quantity * $orderItem->qty;
                    
                    // Deduct stock (negative quantity)
                    InventoryService::recordMovement(
                        itemId: $recipeItem->inventory_item_id,
                        warehouseId: $warehouse->id,
                        quantity: -$qtyDeducted,
                        type: 'consume',
                        unitCost: (float) $recipeItem->unit_cost,
                        referenceType: get_class($order),
                        referenceId: $order->id,
                        referenceNumber: $order->receipt_number,
                        reason: "Order deduction for item {$orderItem->snapshot_name}",
                        userId: $order->user_id
                    );

                    // Add up COGS contribution
                    $cogsTotal += (float) $recipeItem->total_cost * $orderItem->qty;
                }
            }

            // Write final computed COGS to the order item
            $orderItem->update([
                'cogs_total' => $cogsTotal
            ]);
        }

        // 3. Compute and save order level cogs_total and gross_profit
        $order->refresh();
        $totalCogs = (float) $order->items()->sum('cogs_total');
        $netSales = (float) $order->subtotal - (float) $order->discount_total;
        $grossProfit = $netSales - $totalCogs;

        $order->update([
            'cogs_total' => $totalCogs,
            'gross_profit' => $grossProfit,
        ]);
    }
}
