<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Recipe;
use App\Models\RecipeVersion;
use Illuminate\Http\Request;

class RecipeController extends Controller
{
    public function index(Request $request)
    {
        return Recipe::with(['items', 'versions'])
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->integer('product_id'), fn ($query, $productId) => $query->where('product_id', $productId))
            ->paginate(100);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'product_id' => 'nullable|integer|exists:products,id',
            'name' => 'required|string|max:255',
            'status' => 'nullable|string|max:50',
            'yield_quantity' => 'nullable|numeric',
            'yield_unit' => 'nullable|string|max:50',
            'items' => 'nullable|array',
            'items.*.inventory_item_id' => 'nullable|integer|exists:inventory_items,id',
            'items.*.child_recipe_id' => 'nullable|integer|exists:recipes,id',
            'items.*.quantity' => 'required_with:items|numeric',
            'items.*.unit' => 'nullable|string|max:50',
            'items.*.waste_percent' => 'nullable|numeric',
            'items.*.unit_cost' => 'nullable|numeric',
            'items.*.notes' => 'nullable|string',
        ]);

        $recipe = Recipe::create(collect($validated)->except('items')->all());
        $version = $recipe->versions()->create([
            'version' => 1,
            'status' => $recipe->status,
            'effective_at' => now(),
        ]);

        foreach ($validated['items'] ?? [] as $item) {
            $recipe->items()->create([
                ...$item,
                'recipe_version_id' => $version->id,
                'total_cost' => ($item['quantity'] ?? 0) * ($item['unit_cost'] ?? 0),
            ]);
        }

        $this->recalculateCost($recipe);

        return response()->json($recipe->load(['items', 'versions']), 201);
    }

    public function update(Request $request, Recipe $recipe)
    {
        $recipe->update($request->validate([
            'product_id' => 'nullable|integer|exists:products,id',
            'name' => 'sometimes|string|max:255',
            'status' => 'nullable|string|max:50',
            'yield_quantity' => 'nullable|numeric',
            'yield_unit' => 'nullable|string|max:50',
        ]));

        return response()->json($recipe->load(['items', 'versions']));
    }

    public function version(Request $request)
    {
        $validated = $request->validate([
            'recipe_id' => 'required|integer|exists:recipes,id',
            'status' => 'nullable|string|max:50',
            'effective_at' => 'nullable|date',
        ]);

        $recipe = Recipe::findOrFail($validated['recipe_id']);
        $nextVersion = ((int) $recipe->versions()->max('version')) + 1;

        $version = RecipeVersion::create([
            'recipe_id' => $recipe->id,
            'version' => $nextVersion,
            'total_cost' => $recipe->current_cost,
            'status' => $validated['status'] ?? 'draft',
            'effective_at' => $validated['effective_at'] ?? null,
        ]);

        return response()->json($version, 201);
    }

    public function costing(Request $request)
    {
        return Recipe::query()
            ->select(['id', 'product_id', 'name', 'current_cost', 'yield_quantity', 'yield_unit', 'active_version'])
            ->when($request->integer('product_id'), fn ($query, $productId) => $query->where('product_id', $productId))
            ->paginate(100);
    }

    private function recalculateCost(Recipe $recipe): void
    {
        $recipe->update([
            'current_cost' => $recipe->items()->sum('total_cost'),
        ]);
    }
}
