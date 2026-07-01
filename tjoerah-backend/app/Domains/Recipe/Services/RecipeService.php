<?php

namespace App\Domains\Recipe\Services;

use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Recipe\Models\RecipeItem;
use App\Domains\Recipe\Models\RecipeVersion;
use App\Domains\Recipe\Models\Recipe;

class RecipeService
{
    /**
     * Recalculate recipe costs when an inventory item's average cost is updated.
     */
    public static function recalculateRecipeCostsUsingItem(int $itemId): void
    {
        $item = InventoryItem::find($itemId);
        if (!$item) {
            return;
        }

        // Find all recipe items referencing this inventory item
        $recipeItems = RecipeItem::where('inventory_item_id', $itemId)->get();

        foreach ($recipeItems as $recipeItem) {
            $unitCost = (float) $item->weighted_average_cost;
            $wasteFactor = 1 + ((float) $recipeItem->waste_percent / 100);
            $totalCost = (float) $recipeItem->quantity * $unitCost * $wasteFactor;

            $recipeItem->update([
                'unit_cost' => $unitCost,
                'total_cost' => $totalCost,
            ]);

            // Update parent recipe version total cost
            if ($recipeItem->recipe_version_id) {
                self::updateRecipeVersionTotalCost($recipeItem->recipe_version_id);
            }
        }
    }

    /**
     * Recalculate the total cost of a recipe version.
     */
    public static function updateRecipeVersionTotalCost(int $versionId): void
    {
        $version = RecipeVersion::find($versionId);
        if (!$version) {
            return;
        }

        // Sum the total cost of all recipe items under this version
        $totalItemsCost = (float) RecipeItem::where('recipe_version_id', $versionId)->sum('total_cost');
        
        $version->update([
            'total_cost' => $totalItemsCost
        ]);

        // Propagate cost to parent Recipe
        $recipe = Recipe::find($version->recipe_id);
        if ($recipe && $recipe->active_version == $version->version) {
            $yieldQty = (float) $recipe->yield_quantity ?: 1.0;
            $currentCostPerYield = $totalItemsCost / $yieldQty;
            
            $recipe->update([
                'current_cost' => $currentCostPerYield
            ]);
        }
    }
}
