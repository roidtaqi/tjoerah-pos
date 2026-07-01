<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SyncBatch;
use App\Models\SyncConflict;
use Illuminate\Http\Request;

class SyncController extends Controller
{
    public function pull()
    {
        return response()->json([
            'server_time' => now()->toISOString(),
            'strategy' => [
                'orders' => 'append_only',
                'inventory' => 'stock_movement_reconciliation',
                'recipes' => 'version_based',
                'customers' => 'latest_timestamp',
                'employees' => 'version_based',
            ],
        ]);
    }

    public function push(Request $request)
    {
        $validated = $request->validate([
            'device_id' => 'nullable|string|max:255',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'operations' => 'required|array',
            'operations.*.entity_type' => 'required|string',
            'operations.*.entity_id' => 'required|string',
            'operations.*.operation' => 'required|string|in:CREATE,UPDATE,DELETE,UPSERT',
            'operations.*.payload' => 'nullable|array',
        ]);

        $batch = SyncBatch::create([
            'user_id' => $request->user()?->id,
            'outlet_id' => $validated['outlet_id'] ?? null,
            'device_id' => $validated['device_id'] ?? null,
            'status' => 'completed',
            'processed_count' => count($validated['operations']),
            'failed_count' => 0,
        ]);

        return response()->json([
            'batch' => $batch,
            'accepted' => count($validated['operations']),
            'conflicts' => [],
        ], 202);
    }

    public function conflicts()
    {
        return SyncConflict::where('status', 'open')->latest()->paginate(100);
    }
}
