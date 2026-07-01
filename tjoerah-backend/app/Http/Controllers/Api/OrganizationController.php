<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Brand;
use App\Models\Company;
use Illuminate\Http\Request;

class OrganizationController extends Controller
{
    public function companies()
    {
        return Company::with('brands.outlets')->paginate(50);
    }

    public function storeCompany(Request $request)
    {
        $company = Company::create($request->validate([
            'name' => 'required|string|max:255',
            'legal_name' => 'nullable|string|max:255',
            'tax_number' => 'nullable|string|max:100',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'address' => 'nullable|string',
            'is_active' => 'boolean',
        ]));

        return response()->json($company, 201);
    }

    public function brands(Request $request)
    {
        return Brand::with('company', 'outlets')
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->paginate(50);
    }

    public function storeBrand(Request $request)
    {
        $brand = Brand::create($request->validate([
            'company_id' => 'required|integer|exists:companies,id',
            'name' => 'required|string|max:255',
            'code' => 'nullable|string|max:50',
            'is_active' => 'boolean',
        ]));

        return response()->json($brand, 201);
    }
}
