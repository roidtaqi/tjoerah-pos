<?php

namespace App\Domains\POS\Controllers;

use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\ModifierGroup;
use App\Domains\POS\Models\Product;
use App\Http\Controllers\Controller;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class ProductCatalogController extends Controller
{
    public function sync(Request $request)
    {
        $categories = Category::with([
            'children' => fn ($query) => $query->where('is_active', true)->orderBy('sort_order'),
        ])
            ->whereNull('parent_id')
            ->where('is_active', true)
            ->when($request->user()?->company_id, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->orderBy('sort_order')
            ->get();
        $products = $this->productQuery($request)
            ->where('is_active', true)
            ->orderBy('name')
            ->get();

        return response()->json([
            'categories' => $categories,
            'products' => $products,
        ]);
    }

    public function getProducts(Request $request)
    {
        $request->validate([
            'per_page' => 'nullable|integer|min:1|max:100',
            'status' => ['nullable', Rule::in(['active', 'inactive', 'all'])],
            'q' => 'nullable|string|max:255',
        ]);

        $query = $this->productQuery($request)
            ->when($request->integer('brand_id'), fn ($query, $brandId) => $query->where('brand_id', $brandId))
            ->when($request->integer('category_id'), fn ($query, $categoryId) => $query->where('category_id', $categoryId))
            ->when($request->string('q')->trim()->isNotEmpty(), function ($query) use ($request) {
                $term = $request->string('q')->trim()->toString();
                $query->where(fn ($search) => $search
                    ->where('name', 'like', "%{$term}%")
                    ->orWhere('sku', 'like', "%{$term}%")
                    ->orWhere('barcode', 'like', "%{$term}%"));
            });

        if ($request->input('status') === 'active') {
            $query->where('is_active', true);
        } elseif ($request->input('status') === 'inactive') {
            $query->where('is_active', false);
        }

        return $query->orderBy('name')->paginate($request->integer('per_page', 50));
    }

    public function showProduct(Request $request, Product $product)
    {
        $this->ensureProductIsAccessible($request, $product);

        return response()->json($product->load(['variants', 'modifierGroups.options', 'category']));
    }

    public function search(Request $request)
    {
        $request->validate(['q' => 'required|string|min:1']);
        $q = $request->string('q')->toString();

        return $this->productQuery($request)
            ->where('is_active', true)
            ->where(fn ($query) => $query
                ->where('name', 'like', "%{$q}%")
                ->orWhere('sku', 'like', "%{$q}%")
                ->orWhere('barcode', 'like', "%{$q}%"))
            ->limit(50)
            ->get();
    }

    public function storeProduct(Request $request)
    {
        $this->normalizeNullableProductFields($request);
        $validated = $request->validate($this->productRules());

        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }

        $product = Product::create($validated);

        return response()->json(
            $product->load(['variants', 'modifierGroups.options', 'category']),
            201,
        );
    }

    public function updateProduct(Request $request, Product $product)
    {
        $this->ensureProductIsAccessible($request, $product);
        $this->normalizeNullableProductFields($request);

        $validated = $request->validate($this->productRules($product));
        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }
        $product->update($validated);

        return response()->json($product->fresh()->load([
            'variants',
            'modifierGroups.options',
            'category',
        ]));
    }

    public function destroyProduct(Request $request, Product $product)
    {
        $this->ensureProductIsAccessible($request, $product);
        $product->delete();

        return response()->noContent();
    }

    private function productRules(?Product $product = null): array
    {
        $presence = $product ? 'sometimes' : 'required';

        return [
            'company_id' => 'nullable|exists:companies,id',
            'brand_id' => 'nullable|exists:brands,id',
            'name' => [$presence, 'string', 'max:255'],
            'description' => 'nullable|string|max:5000',
            'category_id' => 'nullable|exists:categories,id',
            'base_price' => [$presence, 'numeric', 'min:0'],
            'sku' => ['nullable', 'string', 'max:100', Rule::unique('products', 'sku')->ignore($product)],
            'barcode' => ['nullable', 'string', 'max:100', Rule::unique('products', 'barcode')->ignore($product)],
            'image_url' => 'nullable|url:http,https|max:2048',
            'product_type' => ['nullable', Rule::in(['simple', 'variant', 'combo', 'bundle'])],
            'station' => ['nullable', Rule::in(['bar', 'kitchen'])],
            'sla_minutes' => 'nullable|integer|min:1|max:1440',
            'track_inventory' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    private function productQuery(Request $request): Builder
    {
        return Product::with(['variants', 'modifierGroups.options', 'category'])
            ->when(
                $request->user()?->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
                fn ($query) => $query->when(
                    $request->integer('company_id'),
                    fn ($query, $companyId) => $query->where('company_id', $companyId),
                ),
            );
    }

    private function ensureProductIsAccessible(Request $request, Product $product): void
    {
        $companyId = $request->user()?->company_id;
        abort_if($companyId && (int) $product->company_id !== (int) $companyId, 404);
    }

    private function normalizeNullableProductFields(Request $request): void
    {
        foreach (['company_id', 'brand_id', 'category_id', 'description', 'sku', 'barcode', 'image_url', 'station', 'sla_minutes'] as $field) {
            if ($request->exists($field) && trim((string) $request->input($field)) === '') {
                $request->merge([$field => null]);
            }
        }
    }

    public function categories(Request $request)
    {
        return Category::with('children')
            ->when(
                $request->user()?->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
                fn ($query) => $query->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId)),
            )
            ->when($request->integer('brand_id'), fn ($query, $brandId) => $query->where('brand_id', $brandId))
            ->whereNull('parent_id')
            ->orderBy('sort_order')
            ->paginate(100);
    }

    public function showCategory(Request $request, Category $category)
    {
        $this->ensureCategoryIsAccessible($request, $category);

        return response()->json($category->load(['parent', 'children']));
    }

    public function storeCategory(Request $request)
    {
        $this->normalizeNullableCategoryFields($request);
        $validated = $request->validate($this->categoryRules());
        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }
        $this->validateCategoryParent($request, $validated);
        $category = Category::create($validated);

        return response()->json($category->load(['parent', 'children']), 201);
    }

    public function updateCategory(Request $request, Category $category)
    {
        $this->ensureCategoryIsAccessible($request, $category);
        $this->normalizeNullableCategoryFields($request);

        $validated = $request->validate($this->categoryRules($category));
        if ($request->user()?->company_id) {
            $validated['company_id'] = $request->user()->company_id;
        }
        $this->validateCategoryParent($request, $validated, $category);
        $category->update($validated);

        return response()->json($category->fresh()->load(['parent', 'children']));
    }

    public function destroyCategory(Request $request, Category $category)
    {
        $this->ensureCategoryIsAccessible($request, $category);

        if ($category->children()->exists()) {
            throw ValidationException::withMessages([
                'category' => 'Kategori masih memiliki subkategori. Pindahkan atau hapus subkategori terlebih dahulu.',
            ]);
        }
        if ($category->products()->exists()) {
            throw ValidationException::withMessages([
                'category' => 'Kategori masih digunakan oleh produk. Pindahkan produk terlebih dahulu.',
            ]);
        }

        $category->delete();

        return response()->noContent();
    }

    private function categoryRules(?Category $category = null): array
    {
        $presence = $category ? 'sometimes' : 'required';

        return [
            'company_id' => 'nullable|exists:companies,id',
            'brand_id' => 'nullable|exists:brands,id',
            'parent_id' => 'nullable|exists:categories,id',
            'name' => [$presence, 'string', 'max:255'],
            'sort_order' => 'nullable|integer|min:0',
            'is_active' => 'boolean',
        ];
    }

    private function validateCategoryParent(
        Request $request,
        array $validated,
        ?Category $category = null,
    ): void {
        if (! array_key_exists('parent_id', $validated) || $validated['parent_id'] === null) {
            return;
        }

        $parent = Category::findOrFail($validated['parent_id']);
        $this->ensureCategoryIsAccessible($request, $parent);

        $companyId = $request->user()?->company_id
            ?? ($validated['company_id'] ?? $category?->company_id);
        if ((string) ($parent->company_id ?? '') !== (string) ($companyId ?? '')) {
            throw ValidationException::withMessages([
                'parent_id' => 'Kategori induk harus berada di perusahaan yang sama.',
            ]);
        }

        for ($ancestor = $parent; $ancestor !== null; $ancestor = $ancestor->parent) {
            if ($category && (int) $ancestor->id === (int) $category->id) {
                throw ValidationException::withMessages([
                    'parent_id' => 'Kategori tidak dapat dijadikan anak dari dirinya sendiri atau turunannya.',
                ]);
            }
        }
    }

    private function ensureCategoryIsAccessible(Request $request, Category $category): void
    {
        $companyId = $request->user()?->company_id;
        abort_if($companyId && (int) $category->company_id !== (int) $companyId, 404);
    }

    private function normalizeNullableCategoryFields(Request $request): void
    {
        foreach (['company_id', 'brand_id', 'parent_id', 'sort_order'] as $field) {
            if ($request->exists($field) && trim((string) $request->input($field)) === '') {
                $request->merge([$field => null]);
            }
        }
    }

    public function modifierGroups(Request $request)
    {
        return ModifierGroup::with('options')
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->paginate(100);
    }
}
