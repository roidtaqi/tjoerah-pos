<?php

namespace App\Domains\Recipe\Services;

use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeItem;
use App\Domains\Recipe\Models\RecipeVersion;

class RecipeService
{
    /**
     * Recalculate recipe costs when an inventory item's average cost is updated.
     */
    public static function recalculateRecipeCostsUsingItem(int $itemId): void
    {
        $item = InventoryItem::find($itemId);
        if (! $item) {
            return;
        }

        // Historical recipe versions are immutable cost snapshots. Only the
        // ingredients belonging to each recipe's active version are refreshed.
        $recipeItems = RecipeItem::query()
            ->select('recipe_items.*')
            ->join('recipe_versions', 'recipe_versions.id', '=', 'recipe_items.recipe_version_id')
            ->join('recipes', 'recipes.id', '=', 'recipe_items.recipe_id')
            ->where('recipe_items.inventory_item_id', $itemId)
            ->whereNull('recipes.deleted_at')
            ->whereColumn('recipe_versions.version', 'recipes.active_version')
            ->get();
        $affectedVersions = [];

        foreach ($recipeItems as $recipeItem) {
            $unitCost = (float) $item->weighted_average_cost;
            $wasteFactor = 1 + ((float) $recipeItem->waste_percent / 100);
            $totalCost = (float) $recipeItem->quantity * $unitCost * $wasteFactor;

            $recipeItem->update([
                'unit_cost' => $unitCost,
                'total_cost' => $totalCost,
            ]);

            if ($recipeItem->recipe_version_id) {
                $affectedVersions[] = (int) $recipeItem->recipe_version_id;
            }
        }

        foreach (array_unique($affectedVersions) as $versionId) {
            self::updateRecipeVersionTotalCost($versionId);
        }
    }

    /**
     * Recalculate the total cost of a recipe version.
     */
    public static function updateRecipeVersionTotalCost(int $versionId): void
    {
        $version = RecipeVersion::find($versionId);
        if (! $version) {
            return;
        }

        $totalItemsCost = (float) RecipeItem::where('recipe_version_id', $versionId)->sum('total_cost');

        $version->update([
            'total_cost' => $totalItemsCost,
        ]);

        $recipe = Recipe::find($version->recipe_id);
        if ($recipe && $recipe->active_version === $version->version) {
            $yieldQty = (float) $recipe->yield_quantity ?: 1.0;
            $currentCostPerYield = $totalItemsCost / $yieldQty;

            $recipe->update([
                'current_cost' => $currentCostPerYield,
            ]);
        }
    }
}
