<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\KitchenTicket;
use Illuminate\Http\Request;

class KdsController extends Controller
{
    public function tickets(Request $request)
    {
        return KitchenTicket::with(['items', 'order'])
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($request->string('station')->isNotEmpty(), fn ($query) => $query->where('station', request('station')))
            ->when($request->string('status')->isNotEmpty(), fn ($query) => $query->where('status', request('status')))
            ->orderByRaw("CASE priority WHEN 'rush' THEN 0 WHEN 'vip' THEN 1 ELSE 2 END")
            ->oldest()
            ->paginate(100);
    }

    public function updateStatus(Request $request, KitchenTicket $ticket)
    {
        $validated = $request->validate([
            'status' => 'required|string|in:pending,accepted,preparing,ready,completed',
        ]);

        $timestampColumn = match ($validated['status']) {
            'accepted' => 'accepted_at',
            'preparing' => 'preparing_at',
            'ready' => 'ready_at',
            'completed' => 'completed_at',
            default => null,
        };

        $updates = ['status' => $validated['status']];
        if ($timestampColumn) {
            $updates[$timestampColumn] = now();
        }

        $ticket->update($updates);

        return response()->json($ticket->load('items'));
    }
}
