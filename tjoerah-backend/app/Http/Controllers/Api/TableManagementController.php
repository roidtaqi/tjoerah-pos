<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DiningTable;
use App\Models\Floor;
use App\Models\TableSession;
use Illuminate\Http\Request;

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
            'status' => 'nullable|string|max:50',
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
            'status' => 'nullable|string|max:50',
            'position_x' => 'nullable|integer',
            'position_y' => 'nullable|integer',
        ]));

        return response()->json($table);
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
