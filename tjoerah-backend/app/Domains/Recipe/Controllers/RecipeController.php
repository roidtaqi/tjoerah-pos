<?php

namespace App\Domains\Recipe\Controllers;

use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\POS\Models\Product;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeVersion;
use App\Http\Controllers\Controller;
use App\Support\CsvTable;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class RecipeController extends Controller
{
    public function index(Request $request)
    {
        $request->validate([
            'per_page' => 'nullable|integer|min:1|max:100',
            'product_id' => 'nullable|integer',
            'status' => ['nullable', Rule::in(['draft', 'active', 'inactive', 'all'])],
            'q' => 'nullable|string|max:255',
        ]);

        $query = $this->recipeQuery($request)
            ->when($request->integer('product_id'), fn ($query, $productId) => $query->where('product_id', $productId))
            ->when(
                $request->string('q')->trim()->isNotEmpty(),
                fn ($query) => $query->where('name', 'like', '%'.$request->string('q')->trim()->toString().'%'),
            );

        if ($request->input('status') && $request->input('status') !== 'all') {
            $query->where('status', $request->input('status'));
        }

        $recipes = $query
            ->orderBy('name')
            ->paginate($request->integer('per_page', 100));
        $recipes->getCollection()->transform(
            fn (Recipe $recipe) => $this->serializeRecipe($recipe),
        );

        return $recipes;
    }

    public function store(Request $request)
    {
        $this->normalizeNullableFields($request);
        $validated = $request->validate($this->recipeRules());
        $companyId = $request->user()?->company_id ?? ($validated['company_id'] ?? null);

        $this->validateAssociations(
            $validated,
            $companyId ? (int) $companyId : null,
        );

        $recipe = DB::transaction(function () use ($request, $validated, $companyId) {
            $recipe = Recipe::create([
                'company_id' => $companyId,
                'product_id' => $validated['product_id'] ?? null,
                'name' => $validated['name'],
                'status' => $validated['status'],
                'active_version' => 1,
                'yield_quantity' => $validated['yield_quantity'],
                'yield_unit' => $validated['yield_unit'],
                'current_cost' => 0,
            ]);

            $this->createVersion(
                $recipe,
                $validated['items'],
                1,
                $validated['status'],
                $request->user()?->id,
            );

            return $recipe;
        });

        return response()->json(
            $this->loadAndSerialize($recipe),
            201,
        );
    }

    public function update(Request $request, Recipe $recipe)
    {
        $this->ensureRecipeIsAccessible($request, $recipe);
        $this->normalizeNullableFields($request);
        $validated = $request->validate($this->recipeRules($recipe));
        $companyId = $request->user()?->company_id ?? $recipe->company_id;

        $this->validateAssociations(
            $validated,
            $companyId ? (int) $companyId : null,
            $recipe,
        );

        DB::transaction(function () use ($request, $validated, $recipe, $companyId) {
            $nextVersion = ((int) $recipe->versions()->max('version')) + 1;

            $recipe->update([
                'company_id' => $companyId,
                'product_id' => $validated['product_id'] ?? null,
                'name' => $validated['name'],
                'status' => $validated['status'],
                'active_version' => $nextVersion,
                'yield_quantity' => $validated['yield_quantity'],
                'yield_unit' => $validated['yield_unit'],
            ]);

            $this->createVersion(
                $recipe,
                $validated['items'],
                $nextVersion,
                $validated['status'],
                $request->user()?->id,
            );
        });

        return response()->json($this->loadAndSerialize($recipe));
    }

    public function destroy(Request $request, Recipe $recipe)
    {
        $this->ensureRecipeIsAccessible($request, $recipe);
        $recipe->delete();

        return response()->noContent();
    }

    public function version(Request $request)
    {
        $validated = $request->validate([
            'recipe_id' => 'required|integer|exists:recipes,id',
            'status' => ['nullable', Rule::in(['draft', 'active', 'inactive'])],
        ]);

        $recipe = Recipe::findOrFail($validated['recipe_id']);
        $this->ensureRecipeIsAccessible($request, $recipe);
        $recipe->load('latestVersionRecord.items');

        $sourceItems = $recipe->latestVersionRecord?->items
            ->map(fn ($item) => [
                'inventory_item_id' => $item->inventory_item_id,
                'quantity' => $item->quantity,
                'waste_percent' => $item->waste_percent,
                'notes' => $item->notes,
            ])
            ->all() ?? [];

        if ($sourceItems === []) {
            throw ValidationException::withMessages([
                'items' => 'Versi resep aktif belum memiliki bahan.',
            ]);
        }

        $nextVersion = DB::transaction(function () use ($request, $validated, $recipe, $sourceItems) {
            $nextVersion = ((int) $recipe->versions()->max('version')) + 1;
            $status = $validated['status'] ?? $recipe->status;
            $recipe->update([
                'status' => $status,
                'active_version' => $nextVersion,
            ]);
            $this->createVersion(
                $recipe,
                $sourceItems,
                $nextVersion,
                $status,
                $request->user()?->id,
            );

            return $nextVersion;
        });

        return response()->json(
            $recipe->versions()->where('version', $nextVersion)->firstOrFail(),
            201,
        );
    }

    public function costing(Request $request)
    {
        return $this->recipeQuery($request)
            ->select([
                'id',
                'product_id',
                'name',
                'status',
                'current_cost',
                'yield_quantity',
                'yield_unit',
                'active_version',
            ])
            ->when($request->integer('product_id'), fn ($query, $productId) => $query->where('product_id', $productId))
            ->orderBy('name')
            ->paginate(100);
    }

    public function template(Request $request)
    {
        $companyId = $request->user()?->company_id;
        $product = Product::query()
            ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
            ->where('is_active', true)
            ->orderBy('name')
            ->first();
        $ingredients = InventoryItem::query()
            ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
            ->where('is_active', true)
            ->orderBy('name')
            ->limit(2)
            ->get();

        $sampleIngredients = $ingredients->isNotEmpty()
            ? $ingredients
            : collect([(object) [
                'name' => 'Nama bahan persediaan',
                'sku' => '',
                'unit' => 'g',
            ]]);
        $productName = $product?->name ?? 'Nama produk di aplikasi';
        $rows = $sampleIngredients->values()->map(
            fn ($ingredient, $index) => [
                "Resep {$productName}",
                $productName,
                'draft',
                1,
                'porsi',
                $ingredient->name,
                $ingredient->sku ?? '',
                $index === 0 ? 10 : 20,
                $ingredient->unit ?: 'pcs',
                0,
                '',
            ],
        )->all();

        return CsvTable::download(
            'template-resep.csv',
            [
                'recipe_name',
                'product_name',
                'status',
                'yield_quantity',
                'yield_unit',
                'ingredient_name',
                'ingredient_sku',
                'quantity',
                'unit',
                'waste_percent',
                'notes',
            ],
            $rows,
        );
    }

    public function import(Request $request)
    {
        $validated = $request->validate([
            'file' => 'required|file|max:5120',
        ]);
        $rows = CsvTable::read($validated['file']);
        CsvTable::requireHeaders($rows, [
            'recipe_name',
            'product_name',
            'status',
            'yield_quantity',
            'yield_unit',
            'ingredient_name',
            'quantity',
        ]);

        $companyId = $request->user()?->company_id;
        $groups = collect($rows)->groupBy(
            fn ($row) => mb_strtolower(trim($row['product_name'])),
        );
        $created = 0;
        $updated = 0;

        DB::transaction(function () use (
            $groups,
            $companyId,
            $request,
            &$created,
            &$updated,
        ): void {
            foreach ($groups as $group) {
                $first = $group->first();
                $line = (int) $first['_line'];
                $productName = trim($first['product_name']);
                $recipeName = trim($first['recipe_name']);
                $status = trim($first['status']) ?: 'draft';
                $yieldQuantity = (float) $first['yield_quantity'];
                $yieldUnit = trim($first['yield_unit']);

                $this->validateImportedRecipeHeader(
                    $line,
                    $recipeName,
                    $productName,
                    $status,
                    $yieldQuantity,
                    $yieldUnit,
                );
                $product = Product::query()
                    ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
                    ->whereRaw('LOWER(name) = ?', [mb_strtolower($productName)])
                    ->first();
                if (! $product) {
                    $this->importError(
                        $line,
                        "Produk '{$productName}' tidak ditemukan.",
                    );
                }

                $items = $group->map(function (array $row) use ($companyId) {
                    $line = (int) $row['_line'];
                    $ingredientName = trim($row['ingredient_name']);
                    $sku = trim($row['ingredient_sku'] ?? '');
                    $quantity = (float) $row['quantity'];
                    $wastePercent = (float) ($row['waste_percent'] ?: 0);
                    if ($ingredientName === '' || $quantity <= 0) {
                        $this->importError(
                            $line,
                            'Nama bahan dan quantity lebih dari 0 wajib diisi.',
                        );
                    }
                    if ($wastePercent < 0 || $wastePercent > 100) {
                        $this->importError(
                            $line,
                            'Waste percent harus berada di antara 0 dan 100.',
                        );
                    }

                    $ingredient = InventoryItem::query()
                        ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
                        ->when(
                            $sku !== '',
                            fn ($query) => $query->whereRaw('LOWER(sku) = ?', [mb_strtolower($sku)]),
                            fn ($query) => $query->whereRaw('LOWER(name) = ?', [mb_strtolower($ingredientName)]),
                        )
                        ->first();
                    if (! $ingredient) {
                        $reference = $sku !== '' ? "SKU {$sku}" : $ingredientName;
                        $this->importError(
                            $line,
                            "Bahan '{$reference}' tidak ditemukan.",
                        );
                    }

                    return [
                        'inventory_item_id' => $ingredient->id,
                        'quantity' => $quantity,
                        'waste_percent' => $wastePercent,
                        'notes' => trim($row['notes'] ?? '') ?: null,
                    ];
                })->values()->all();

                $duplicateIngredient = collect($items)
                    ->groupBy('inventory_item_id')
                    ->first(fn ($items) => $items->count() > 1);
                if ($duplicateIngredient) {
                    $this->importError(
                        $line,
                        'Satu bahan tidak boleh muncul dua kali dalam resep yang sama.',
                    );
                }

                $recipe = Recipe::query()
                    ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
                    ->where('product_id', $product->id)
                    ->first();
                $versionNumber = $recipe
                    ? ((int) $recipe->versions()->max('version')) + 1
                    : 1;
                if ($recipe) {
                    $recipe->update([
                        'name' => $recipeName,
                        'status' => $status,
                        'active_version' => $versionNumber,
                        'yield_quantity' => $yieldQuantity,
                        'yield_unit' => $yieldUnit,
                    ]);
                    $updated++;
                } else {
                    $recipe = Recipe::create([
                        'company_id' => $companyId,
                        'product_id' => $product->id,
                        'name' => $recipeName,
                        'status' => $status,
                        'active_version' => 1,
                        'yield_quantity' => $yieldQuantity,
                        'yield_unit' => $yieldUnit,
                        'current_cost' => 0,
                    ]);
                    $created++;
                }

                $this->createVersion(
                    $recipe,
                    $items,
                    $versionNumber,
                    $status,
                    $request->user()?->id,
                );
            }
        });

        return response()->json([
            'message' => 'Impor resep berhasil.',
            'imported_recipes' => $created + $updated,
            'created' => $created,
            'updated' => $updated,
        ]);
    }

    private function recipeRules(?Recipe $recipe = null): array
    {
        return [
            'company_id' => 'nullable|integer|exists:companies,id',
            'product_id' => 'nullable|integer|exists:products,id',
            'name' => 'required|string|max:255',
            'status' => ['required', Rule::in(['draft', 'active', 'inactive'])],
            'yield_quantity' => 'required|numeric|gt:0',
            'yield_unit' => 'required|string|max:50',
            'items' => 'required|array|min:1',
            'items.*.inventory_item_id' => 'required|integer|distinct|exists:inventory_items,id',
            'items.*.quantity' => 'required|numeric|gt:0',
            'items.*.waste_percent' => 'nullable|numeric|min:0|max:100',
            'items.*.notes' => 'nullable|string|max:2000',
        ];
    }

    private function validateAssociations(
        array $validated,
        ?int $companyId,
        ?Recipe $recipe = null,
    ): void {
        $productId = $validated['product_id'] ?? null;
        if ($productId) {
            $product = Product::query()
                ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
                ->find($productId);
            if (! $product) {
                throw ValidationException::withMessages([
                    'product_id' => 'Produk tidak tersedia untuk perusahaan ini.',
                ]);
            }

            $duplicate = Recipe::query()
                ->where('product_id', $productId)
                ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
                ->when($recipe, fn ($query) => $query->whereKeyNot($recipe->getKey()))
                ->exists();
            if ($duplicate) {
                throw ValidationException::withMessages([
                    'product_id' => 'Produk ini sudah memiliki resep.',
                ]);
            }
        }

        $itemIds = collect($validated['items'])
            ->pluck('inventory_item_id')
            ->map(fn ($id) => (int) $id)
            ->unique()
            ->values();
        $availableItemIds = InventoryItem::query()
            ->whereIn('id', $itemIds)
            ->when($companyId, fn ($query) => $query->where('company_id', $companyId))
            ->pluck('id')
            ->map(fn ($id) => (int) $id);

        if ($availableItemIds->count() !== $itemIds->count()) {
            throw ValidationException::withMessages([
                'items' => 'Satu atau lebih bahan tidak tersedia untuk perusahaan ini.',
            ]);
        }
    }

    private function createVersion(
        Recipe $recipe,
        array $items,
        int $versionNumber,
        string $status,
        ?int $approvedBy,
    ): RecipeVersion {
        $inventory = $this->inventoryFor($recipe, $items);
        $lines = collect($items)->map(function (array $item) use ($inventory) {
            $inventoryItem = $inventory->get((int) $item['inventory_item_id']);
            $quantity = (float) $item['quantity'];
            $wastePercent = (float) ($item['waste_percent'] ?? 0);
            $unitCost = (float) $inventoryItem->weighted_average_cost;

            return [
                'inventory_item_id' => $inventoryItem->id,
                'quantity' => $quantity,
                'unit' => $inventoryItem->unit ?: 'pcs',
                'waste_percent' => $wastePercent,
                'unit_cost' => $unitCost,
                'total_cost' => $quantity * $unitCost * (1 + ($wastePercent / 100)),
                'notes' => $item['notes'] ?? null,
            ];
        });
        $totalCost = (float) $lines->sum('total_cost');

        $version = $recipe->versions()->create([
            'version' => $versionNumber,
            'total_cost' => $totalCost,
            'waste_percent' => $this->averageWaste($lines),
            'status' => $status,
            'effective_at' => now(),
            'approved_by' => $approvedBy,
        ]);

        foreach ($lines as $line) {
            $recipe->items()->create([
                ...$line,
                'recipe_version_id' => $version->id,
            ]);
        }

        $yieldQuantity = max((float) $recipe->yield_quantity, 0.0001);
        $recipe->update([
            'current_cost' => $totalCost / $yieldQuantity,
        ]);

        return $version;
    }

    private function inventoryFor(Recipe $recipe, array $items): Collection
    {
        $ids = collect($items)->pluck('inventory_item_id')->unique();

        return InventoryItem::query()
            ->whereIn('id', $ids)
            ->when($recipe->company_id, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->get()
            ->keyBy(fn (InventoryItem $item) => (int) $item->id);
    }

    private function averageWaste(Collection $items): float
    {
        if ($items->isEmpty()) {
            return 0;
        }

        return (float) $items->avg('waste_percent');
    }

    private function recipeQuery(Request $request)
    {
        return Recipe::with([
            'product:id,name,base_price,is_active',
            'latestVersionRecord.items.inventoryItem:id,name,sku,unit,weighted_average_cost,is_active',
            'versions' => fn ($query) => $query->latest('version'),
        ])->when(
            $request->user()?->company_id,
            fn ($query, $companyId) => $query->where('company_id', $companyId),
            fn ($query) => $query->when(
                $request->integer('company_id'),
                fn ($query, $companyId) => $query->where('company_id', $companyId),
            ),
        );
    }

    private function ensureRecipeIsAccessible(Request $request, Recipe $recipe): void
    {
        $companyId = $request->user()?->company_id;
        abort_if($companyId && (int) $recipe->company_id !== (int) $companyId, 404);
    }

    private function loadAndSerialize(Recipe $recipe): array
    {
        $recipe->unsetRelations();
        $recipe->load([
            'product:id,name,base_price,is_active',
            'latestVersionRecord.items.inventoryItem:id,name,sku,unit,weighted_average_cost,is_active',
            'versions' => fn ($query) => $query->latest('version'),
        ]);

        return $this->serializeRecipe($recipe);
    }

    private function serializeRecipe(Recipe $recipe): array
    {
        $data = $recipe->attributesToArray();
        $data['product'] = $recipe->product?->toArray();
        $data['items'] = $recipe->latestVersionRecord?->items
            ->map(function ($item) {
                $row = $item->toArray();
                $row['inventory_item_name'] = $item->inventoryItem?->name;
                $row['inventory_item'] = $item->inventoryItem?->toArray();

                return $row;
            })
            ->values()
            ->all() ?? [];
        $data['versions'] = $recipe->versions
            ->map(fn ($version) => $version->toArray())
            ->values()
            ->all();

        return $data;
    }

    private function normalizeNullableFields(Request $request): void
    {
        foreach (['company_id', 'product_id'] as $field) {
            if ($request->exists($field) && trim((string) $request->input($field)) === '') {
                $request->merge([$field => null]);
            }
        }
    }

    private function validateImportedRecipeHeader(
        int $line,
        string $recipeName,
        string $productName,
        string $status,
        float $yieldQuantity,
        string $yieldUnit,
    ): void {
        if ($recipeName === '' || $productName === '' || $yieldUnit === '') {
            $this->importError(
                $line,
                'Nama resep, produk, dan satuan hasil wajib diisi.',
            );
        }
        if (! in_array($status, ['draft', 'active', 'inactive'], true)) {
            $this->importError(
                $line,
                'Status harus draft, active, atau inactive.',
            );
        }
        if ($yieldQuantity <= 0) {
            $this->importError($line, 'Yield quantity harus lebih dari 0.');
        }
    }

    private function importError(int $line, string $message): never
    {
        throw ValidationException::withMessages([
            'file' => "Baris {$line}: {$message}",
        ]);
    }
}
