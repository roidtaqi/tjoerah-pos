<?php

namespace App\Domains\Core\Controllers;

use App\Domains\Core\Models\Outlet;
use Illuminate\Http\Request;

use App\Http\Controllers\Controller;

class OutletController extends Controller
{
    public function index()
    {
        return Outlet::all();
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'address' => 'nullable|string',
            'phone' => 'nullable|string|max:50',
            'is_active' => 'boolean'
        ]);

        $outlet = Outlet::create($validated);
        return response()->json($outlet, 201);
    }

    public function show(Outlet $outlet)
    {
        return $outlet;
    }

    public function update(Request $request, Outlet $outlet)
    {
        $validated = $request->validate([
            'name' => 'sometimes|string|max:255',
            'address' => 'nullable|string',
            'phone' => 'nullable|string|max:50',
            'is_active' => 'boolean'
        ]);

        $outlet->update($validated);
        return response()->json($outlet);
    }

    public function destroy(Outlet $outlet)
    {
        $outlet->delete();
        return response()->json(null, 204);
    }
}
