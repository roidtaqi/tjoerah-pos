<?php

namespace App\Http\Controllers;

use App\Models\Product;
use App\Models\Category;
use App\Models\ModifierGroup;
use Illuminate\Http\Request;

class ProductCatalogController extends Controller
{
    // Fetch the entire catalog for the POS offline sync
    public function sync()
    {
        $categories = Category::with('children')->whereNull('parent_id')->get();
        $products = Product::with(['variants', 'modifierGroups.options', 'category'])->get();

        return response()->json([
            'categories' => $categories,
            'products' => $products,
        ]);
    }

    public function getProducts(Request $request)
    {
        return Product::with(['variants', 'modifierGroups.options', 'category'])
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->integer('brand_id'), fn ($query, $brandId) => $query->where('brand_id', $brandId))
            ->when($request->integer('category_id'), fn ($query, $categoryId) => $query->where('category_id', $categoryId))
            ->paginate(50);
    }

    public function search(Request $request)
    {
        $request->validate(['q' => 'required|string|min:1']);
        $q = $request->string('q')->toString();

        return Product::with(['variants', 'modifierGroups.options', 'category'])
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
        $validated = $request->validate([
            'company_id' => 'nullable|exists:companies,id',
            'brand_id' => 'nullable|exists:brands,id',
            'name' => 'required|string',
            'category_id' => 'nullable|exists:categories,id',
            'base_price' => 'required|numeric',
            'sku' => 'nullable|string|unique:products',
            'barcode' => 'nullable|string|unique:products',
            'product_type' => 'nullable|string',
            'station' => 'nullable|string',
            'sla_minutes' => 'nullable|integer',
            'track_inventory' => 'boolean',
            'is_active' => 'boolean'
        ]);

        $product = Product::create($validated);
        return response()->json($product, 201);
    }

    public function categories(Request $request)
    {
        return Category::with('children')
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->integer('brand_id'), fn ($query, $brandId) => $query->where('brand_id', $brandId))
            ->whereNull('parent_id')
            ->orderBy('sort_order')
            ->paginate(100);
    }

    public function storeCategory(Request $request)
    {
        $category = Category::create($request->validate([
            'company_id' => 'nullable|exists:companies,id',
            'brand_id' => 'nullable|exists:brands,id',
            'parent_id' => 'nullable|exists:categories,id',
            'name' => 'required|string|max:255',
            'sort_order' => 'nullable|integer',
            'is_active' => 'boolean',
        ]));

        return response()->json($category, 201);
    }

    public function modifierGroups(Request $request)
    {
        return ModifierGroup::with('options')
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->paginate(100);
    }
}
