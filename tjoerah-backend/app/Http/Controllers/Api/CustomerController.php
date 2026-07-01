<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Customer;
use App\Models\LoyaltyPoint;
use App\Models\Voucher;
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
            'reference_id' => 'nullable|integer',
            'notes' => 'nullable|string',
        ]);

        $points = LoyaltyPoint::create([
            ...$validated,
            'transaction_type' => 'earn',
        ]);

        return response()->json($points, 201);
    }

    public function redeem(Request $request)
    {
        $validated = $request->validate([
            'customer_id' => 'required|integer|exists:customers,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'points' => 'required|integer|min:1',
            'reference_type' => 'nullable|string|max:255',
            'reference_id' => 'nullable|integer',
            'notes' => 'nullable|string',
        ]);

        $points = LoyaltyPoint::create([
            ...$validated,
            'points' => -1 * abs($validated['points']),
            'transaction_type' => 'redeem',
        ]);

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
