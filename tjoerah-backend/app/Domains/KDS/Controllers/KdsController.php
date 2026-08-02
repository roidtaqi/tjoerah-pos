<?php

namespace App\Domains\KDS\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\KDS\Events\TicketStatusUpdated;
use App\Domains\KDS\Models\KitchenTicket;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class KdsController extends Controller
{
    public function tickets(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'station' => 'nullable|string|max:50',
            'status' => 'nullable|string|in:pending,accepted,preparing,ready,completed,cancelled',
            'per_page' => 'nullable|integer|min:1|max:100',
        ]);
        $outletIds = $this->accessibleOutletIds($request);

        if (isset($validated['outlet_id'])) {
            abort_unless(in_array((int) $validated['outlet_id'], $outletIds, true), 404);
        }

        return KitchenTicket::with('items')
            ->whereIn('outlet_id', $outletIds)
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($validated['station'] ?? null, fn ($query, $station) => $query->where('station', $station))
            ->when(
                $validated['status'] ?? null,
                fn ($query, $status) => $query->where('status', $status),
                fn ($query) => $query->whereIn('status', ['pending', 'accepted', 'preparing', 'ready']),
            )
            ->orderByRaw("CASE priority WHEN 'rush' THEN 0 WHEN 'vip' THEN 1 ELSE 2 END")
            ->oldest()
            ->paginate($validated['per_page'] ?? 50);
    }

    public function updateStatus(Request $request, KitchenTicket $ticket)
    {
        abort_unless(in_array((int) $ticket->outlet_id, $this->accessibleOutletIds($request), true), 404);

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

        event(new TicketStatusUpdated($ticket));

        return response()->json($ticket->load('items'));
    }

    /** @return list<int> */
    private function accessibleOutletIds(Request $request): array
    {
        $user = $request->user();
        $query = $user->company_id
            ? Outlet::query()->where('company_id', $user->company_id)
            : $user->outlets();

        return $query->where('is_active', true)
            ->pluck('outlets.id')
            ->map(fn ($id) => (int) $id)
            ->values()
            ->all();
    }
}
