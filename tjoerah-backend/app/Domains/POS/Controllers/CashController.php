<?php

namespace App\Domains\POS\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Employee\Models\Shift;
use App\Domains\POS\Models\CashMovement;
use App\Domains\POS\Services\CashLedgerService;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class CashController extends Controller
{
    public function __construct(private CashLedgerService $cashLedger) {}

    public function overview(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $manager = $this->isManager($request);
        $current = $this->cashLedger->currentShift($outlet->id, $request->user()->id);
        $recent = Shift::query()
            ->with(['openedBy:id,name', 'closedBy:id,name', 'movements.user:id,name'])
            ->where('outlet_id', $outlet->id)
            ->when(! $manager, fn ($query) => $query->where('opened_by', $request->user()->id))
            ->latest('started_at')
            ->limit($manager ? 30 : 10)
            ->get();

        return response()->json([
            'outlet' => $outlet->only(['id', 'name']),
            'can_adjust' => $manager,
            'current_shift' => $current
                ? $this->serializeShift($current->load(['openedBy:id,name', 'movements.user:id,name']))
                : null,
            'recent_shifts' => $recent->map(fn (Shift $shift) => $this->serializeShift($shift)),
        ]);
    }

    public function open(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'opening_cash' => 'required|numeric|min:0|max:999999999999.99',
            'shift_number' => 'nullable|string|max:100',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $result = $this->cashLedger->openShift(
            $outlet->id,
            $request->user()->id,
            (float) $validated['opening_cash'],
            $request->user()->employee?->id,
            $validated['shift_number'] ?? null,
        );

        return response()->json([
            'message' => $result['existing'] ? 'Sesi kas masih aktif.' : 'Sesi kas berhasil dibuka.',
            'data' => $this->serializeShift($result['shift']->load(['openedBy:id,name', 'movements.user:id,name'])),
        ], $result['existing'] ? 200 : 201);
    }

    public function movement(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'type' => ['required', Rule::in(['cash_in', 'cash_out', 'adjustment_in', 'adjustment_out'])],
            'category' => 'required|string|max:100',
            'amount' => 'required|numeric|min:0.01|max:999999999999.99',
            'note' => 'required|string|min:3|max:1000',
            'client_reference' => 'nullable|string|max:100',
            'photo' => 'nullable|image|max:4096',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        if (str_starts_with($validated['type'], 'adjustment_') && ! $this->isManager($request)) {
            abort(403, 'Hanya owner atau admin yang dapat membuat koreksi kas.');
        }
        $shift = $this->cashLedger->currentShift($outlet->id, $request->user()->id);
        if (! $shift) {
            throw ValidationException::withMessages([
                'shift' => 'Buka sesi kas sebelum mencatat uang masuk atau keluar.',
            ]);
        }
        $path = $request->file('photo')?->store("cash-evidence/{$outlet->id}", 'public');
        $movement = $this->cashLedger->createManualMovement(
            $shift,
            $request->user()->id,
            $validated['type'],
            trim($validated['category']),
            (float) $validated['amount'],
            trim($validated['note']),
            $path,
            $validated['client_reference'] ?? null,
        );

        return response()->json([
            'message' => 'Pergerakan kas berhasil dicatat.',
            'data' => $this->serializeMovement($movement->load('user:id,name')),
            'shift' => $this->serializeShift($shift->fresh()->load(['openedBy:id,name', 'movements.user:id,name'])),
        ], 201);
    }

    public function close(Request $request, Shift $shift)
    {
        $this->ensureShiftAccessible($request, $shift);
        if ($shift->status !== 'open') {
            throw ValidationException::withMessages(['shift' => 'Sesi kas ini sudah ditutup.']);
        }
        $validated = $request->validate([
            'closing_cash' => 'required|numeric|min:0|max:999999999999.99',
            'note' => 'nullable|string|max:1000',
        ]);
        $summary = $this->cashLedger->summary($shift);
        $difference = round((float) $validated['closing_cash'] - (float) $summary['expected_cash'], 2);
        if (abs($difference) > 0.009 && blank($validated['note'] ?? null)) {
            throw ValidationException::withMessages([
                'note' => 'Jelaskan selisih antara uang fisik dan saldo sistem.',
            ]);
        }
        $shift->update([
            'closed_by' => $request->user()->id,
            'ended_at' => now(),
            'closing_cash' => $validated['closing_cash'],
            'status' => 'closed',
        ]);
        if (filled($validated['note'] ?? null)) {
            $shift->movements()->create([
                'outlet_id' => $shift->outlet_id,
                'user_id' => $request->user()->id,
                'type' => 'closing_note',
                'category' => 'cash_reconciliation',
                'amount' => 0,
                'note' => trim($validated['note']),
                'source_key' => "closing:{$shift->id}",
                'occurred_at' => now(),
                'meta' => ['difference' => $difference],
            ]);
        }

        return response()->json([
            'message' => 'Sesi kas berhasil ditutup.',
            'data' => $this->serializeShift($shift->fresh()->load(['openedBy:id,name', 'closedBy:id,name', 'movements.user:id,name'])),
        ]);
    }

    public function evidence(Request $request, CashMovement $cashMovement)
    {
        $this->accessibleOutlet($request, $cashMovement->outlet_id);
        abort_unless($cashMovement->evidence_path, 404);

        return Storage::disk('public')->response($cashMovement->evidence_path);
    }

    private function serializeShift(Shift $shift): array
    {
        $shift->loadMissing('movements.user:id,name');

        return [
            'id' => $shift->id,
            'outlet_id' => $shift->outlet_id,
            'shift_number' => $shift->shift_number,
            'status' => $shift->status,
            'started_at' => $shift->started_at,
            'ended_at' => $shift->ended_at,
            'opened_by' => $shift->openedBy?->only(['id', 'name']),
            'closed_by' => $shift->closedBy?->only(['id', 'name']),
            'summary' => $this->cashLedger->summary($shift),
            'movements' => $shift->movements
                ->sortByDesc('occurred_at')
                ->values()
                ->map(fn (CashMovement $movement) => $this->serializeMovement($movement)),
        ];
    }

    private function serializeMovement(CashMovement $movement): array
    {
        return [
            'id' => $movement->id,
            'shift_id' => $movement->shift_id,
            'type' => $movement->type,
            'category' => $movement->category,
            'amount' => (float) $movement->amount,
            'signed_amount' => $movement->signedAmount(),
            'note' => $movement->note,
            'reference_number' => $movement->reference_number,
            'has_evidence' => filled($movement->evidence_path),
            'occurred_at' => $movement->occurred_at,
            'user' => $movement->user?->only(['id', 'name']),
        ];
    }

    private function accessibleOutlet(Request $request, int $outletId): Outlet
    {
        $user = $request->user();
        $query = Outlet::query()->whereKey($outletId);
        if ($user->company_id) {
            $query->where('company_id', $user->company_id);
        } else {
            $assigned = $user->outlets()->pluck('outlets.id')->map(fn ($id) => (int) $id);
            if ($user->employee?->outlet_id) {
                $assigned->push((int) $user->employee->outlet_id);
            }
            $query->whereIn('id', $assigned->unique()->all());
        }

        return $query->firstOrFail();
    }

    private function ensureShiftAccessible(Request $request, Shift $shift): void
    {
        $this->accessibleOutlet($request, $shift->outlet_id);
        abort_if(
            ! $this->isManager($request) && (int) $shift->opened_by !== (int) $request->user()->id,
            403,
        );
    }

    private function isManager(Request $request): bool
    {
        $roles = collect([$request->user()->role])
            ->merge($request->user()->roles()->pluck('slug'));

        return $roles->contains(fn ($role) => in_array($role, ['owner', 'admin'], true));
    }
}
