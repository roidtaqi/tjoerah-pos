<?php

namespace App\Domains\Core\Controllers;

use App\Http\Controllers\Controller;
use App\Domains\Core\Models\Permission;
use App\Domains\Core\Models\Role;
use App\Domains\Core\Models\User;
use Illuminate\Http\Request;

class RbacController extends Controller
{
    public function roles(Request $request)
    {
        return Role::with('permissions')
            ->when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->paginate(100);
    }

    public function storeRole(Request $request)
    {
        $role = Role::create($request->validate([
            'company_id' => 'nullable|integer|exists:companies,id',
            'name' => 'required|string|max:255',
            'slug' => 'required|string|max:100',
            'scope' => 'nullable|string|max:50',
        ]));

        return response()->json($role, 201);
    }

    public function permissions()
    {
        return Permission::orderBy('module')->orderBy('slug')->get();
    }

    public function attachPermissions(Request $request, Role $role)
    {
        $validated = $request->validate([
            'permission_ids' => 'required|array',
            'permission_ids.*' => 'integer|exists:permissions,id',
        ]);

        $role->permissions()->syncWithoutDetaching($validated['permission_ids']);

        return response()->json($role->load('permissions'));
    }

    public function assignRole(Request $request, User $user)
    {
        $validated = $request->validate([
            'role_id' => 'required|integer|exists:roles,id',
            'company_id' => 'nullable|integer|exists:companies,id',
            'brand_id' => 'nullable|integer|exists:brands,id',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
        ]);

        $user->roles()->attach($validated['role_id'], [
            'company_id' => $validated['company_id'] ?? null,
            'brand_id' => $validated['brand_id'] ?? null,
            'outlet_id' => $validated['outlet_id'] ?? null,
        ]);

        return response()->json($user->load('roles'));
    }
}
