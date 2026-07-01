<?php

namespace App\Domains\CRM\Controllers;

use App\Http\Controllers\Controller;
use App\Domains\CRM\Models\Customer;
use App\Domains\CRM\Models\LoyaltyPoint;
use App\Domains\CRM\Models\Voucher;
use Illuminate\Http\Request;

class CustomerController extends Controller
{
    public function index(Request $request)
    {
        return Customer::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->string('q')->isNotEmpty(), function ($query) use ($request) {
                $q = $request->string('q')->toString();
                $query->where(fn ($nested) => $nested
                    ->where('name', 'like', "%{$q}%")
                    ->orWhere('phone', 'like', "%{$q}%")
                    ->orWhere('email', 'like', "%{$q}%"));
            })
            ->paginate(100);
    }

    public function store(Request $request)
    {
        $customer = Customer::create($request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:50',
            'email' => 'nullable|email|max:255',
            'birthday' => 'nullable|date',
            'notes' => 'nullable|string',
        ]));

        return response()->json($customer, 201);
    }

    public function earn(Request $request)
    {
        $validated = $request->validate([
            'customer_id' => 'required|integer|exists:customers,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'points' => 'required|integer|min:1',
            'reference_type' => 'nullable|string|max:255',
            'reference_id' => 'nullable|string',
            'notes' => 'nullable|string',
        ]);

        $points = \App\Domains\CRM\Services\LoyaltyService::earnPoints(
            customerId: $validated['customer_id'],
            points: $validated['points'],
            refType: $validated['reference_type'] ?? null,
            refId: $validated['reference_id'] ?? null,
            outletId: $validated['outlet_id'] ?? null,
            notes: $validated['notes'] ?? null
        );

        return response()->json($points, 201);
    }

    public function redeem(Request $request)
    {
        $validated = $request->validate([
            'customer_id' => 'required|integer|exists:customers,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'points' => 'required|integer|min:1',
            'reference_type' => 'nullable|string|max:255',
            'reference_id' => 'nullable|string',
            'notes' => 'nullable|string',
        ]);

        $points = \App\Domains\CRM\Services\LoyaltyService::redeemPoints(
            customerId: $validated['customer_id'],
            points: $validated['points'],
            refType: $validated['reference_type'] ?? null,
            refId: $validated['reference_id'] ?? null,
            outletId: $validated['outlet_id'] ?? null,
            notes: $validated['notes'] ?? null
        );

        if (!$points) {
            return response()->json(['message' => 'Insufficient points balance'], 422);
        }

        return response()->json($points, 201);
    }

    public function validateVoucher(Request $request)
    {
        $validated = $request->validate([
            'code' => 'required|string',
            'company_id' => 'nullable|integer|exists:companies,id',
        ]);

        $voucher = Voucher::where('code', $validated['code'])
            ->when($validated['company_id'] ?? null, fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->where('is_active', true)
            ->first();

        return response()->json([
            'valid' => (bool) $voucher,
            'voucher' => $voucher,
        ]);
    }
}
