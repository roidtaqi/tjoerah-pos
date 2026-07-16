<?php

namespace App\Domains\POS\Controllers;

use App\Domains\POS\Models\DiningTable;
use App\Domains\POS\Models\Floor;
use App\Domains\POS\Models\TableSession;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class TableManagementController extends Controller
{
    public function floors(Request $request)
    {
        return Floor::when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->orderBy('sort_order')
            ->paginate(50);
    }

    public function storeFloor(Request $request)
    {
        $floor = Floor::create($request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'name' => 'required|string|max:255',
            'sort_order' => 'nullable|integer',
        ]));

        return response()->json($floor, 201);
    }

    public function updateFloor(Request $request, Floor $floor)
    {
        $floor->update($request->validate([
            'name' => 'sometimes|required|string|max:255',
            'sort_order' => 'sometimes|integer',
        ]));

        return response()->json($floor);
    }

    public function destroyFloor(Floor $floor)
    {
        if (DiningTable::where('floor_id', $floor->id)->exists()) {
            return response()->json([
                'message' => 'Area masih memiliki meja.',
            ], 422);
        }

        $floor->delete();

        return response()->noContent();
    }

    public function tables(Request $request)
    {
        return DiningTable::when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($request->integer('floor_id'), fn ($query, $floorId) => $query->where('floor_id', $floorId))
            ->paginate(100);
    }

    public function storeTable(Request $request)
    {
        $table = DiningTable::create($request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'floor_id' => 'nullable|integer|exists:floors,id',
            'name' => 'required|string|max:255',
            'capacity' => 'nullable|integer|min:1',
            'status' => ['nullable', Rule::in(['available', 'occupied', 'reserved', 'cleaning'])],
            'position_x' => 'nullable|integer',
            'position_y' => 'nullable|integer',
        ]));

        return response()->json($table, 201);
    }

    public function updateTable(Request $request, DiningTable $table)
    {
        $table->update($request->validate([
            'floor_id' => 'nullable|integer|exists:floors,id',
            'name' => 'sometimes|string|max:255',
            'capacity' => 'nullable|integer|min:1',
            'status' => ['nullable', Rule::in(['available', 'occupied', 'reserved', 'cleaning'])],
            'position_x' => 'nullable|integer',
            'position_y' => 'nullable|integer',
        ]));

        return response()->json($table);
    }

    public function destroyTable(DiningTable $table)
    {
        $hasOpenSession = TableSession::where('table_id', $table->id)
            ->where('status', 'open')
            ->exists();

        if ($table->status === 'occupied' || $hasOpenSession) {
            return response()->json([
                'message' => 'Meja yang sedang digunakan tidak dapat dihapus.',
            ], 422);
        }

        $table->delete();

        return response()->noContent();
    }

    public function openSession(Request $request)
    {
        $validated = $request->validate([
            'table_id' => 'required|integer|exists:tables,id',
            'order_id' => 'nullable|integer|exists:orders,id',
        ]);

        $session = TableSession::create([
            ...$validated,
            'status' => 'open',
            'opened_at' => now(),
        ]);

        DiningTable::whereKey($validated['table_id'])->update(['status' => 'occupied']);

        return response()->json($session, 201);
    }

    public function closeSession(TableSession $session)
    {
        $session->update(['status' => 'closed', 'closed_at' => now()]);
        DiningTable::whereKey($session->table_id)->update(['status' => 'cleaning']);

        return response()->json($session);
    }
}
