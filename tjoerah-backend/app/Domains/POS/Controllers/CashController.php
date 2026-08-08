<?php

namespace App\Domains\POS\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Employee\Models\Shift;
use App\Domains\POS\Models\CashMovement;
use App\Domains\POS\Services\CashLedgerService;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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
        $cashOperator = $this->isCashOperator($request);
        $current = $this->cashLedger->currentShift($outlet->id);
        $isOpener = $current
            && (int) $current->opened_by === (int) $request->user()->id;
        $recent = Shift::query()
            ->with(['openedBy:id,name', 'closedBy:id,name', 'movements.user:id,name'])
            ->where('outlet_id', $outlet->id)
            ->latest('started_at')
            ->limit($manager ? 30 : 10)
            ->get();

        return response()->json([
            'outlet' => $outlet->only(['id', 'name']),
            'can_adjust' => false,
            'permissions' => [
                'can_open' => ! $manager && $current === null && $cashOperator,
                'can_record_movement' => ! $manager && $current !== null && $cashOperator,
                'can_close' => ! $manager && (bool) $isOpener && $cashOperator,
                'can_emergency_close' => $manager && $current !== null,
                'monitor_only' => $manager,
                'joined_shared_shift' => ! $manager && $cashOperator && $current !== null && ! $isOpener,
            ],
            'current_shift' => $current
                ? $this->serializeShift($current->load(['openedBy:id,name', 'movements.user:id,name']))
                : null,
            'recent_shifts' => $recent->map(fn (Shift $shift) => $this->serializeShift($shift)),
        ]);
    }

    public function open(Request $request)
    {
        $this->ensureCashOperator($request);
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

        $joined = $result['existing']
            && (int) $result['shift']->opened_by !== (int) $request->user()->id;

        return response()->json([
            'message' => $joined
                ? 'Sesi kas outlet sudah aktif. Anda bergabung ke sesi yang sama.'
                : ($result['existing'] ? 'Sesi kas masih aktif.' : 'Sesi kas berhasil dibuka.'),
            'data' => $this->serializeShift($result['shift']->load(['openedBy:id,name', 'movements.user:id,name'])),
        ], $result['existing'] ? 200 : 201);
    }

    public function movement(Request $request)
    {
        $this->ensureCashOperator($request);
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'type' => ['required', Rule::in(['cash_in', 'cash_out'])],
            'category' => 'required|string|max:100',
            'amount' => 'required|numeric|min:0.01|max:999999999999.99',
            'note' => 'required|string|min:3|max:1000',
            'client_reference' => 'nullable|string|max:100',
            'photo' => 'nullable|image|max:4096',
        ]);
        $outlet = $this->accessibleOutlet($request, (int) $validated['outlet_id']);
        $shift = $this->cashLedger->currentShift($outlet->id);
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
        $this->ensureCashOperator($request);
        $this->accessibleOutlet($request, $shift->outlet_id);
        abort_if(
            (int) $shift->opened_by !== (int) $request->user()->id,
            403,
            'Hanya kasir pembuka yang dapat menutup sesi kas ini.',
        );
        $validated = $request->validate([
            'closing_cash' => 'required|numeric|min:0|max:999999999999.99',
            'note' => 'nullable|string|max:1000',
        ]);

        return $this->completeClose(
            $request,
            $shift,
            (float) $validated['closing_cash'],
            $validated['note'] ?? null,
            false,
        );
    }

    public function emergencyClose(Request $request, Shift $shift)
    {
        abort_unless($this->isManager($request), 403);
        $this->accessibleOutlet($request, $shift->outlet_id);
        $validated = $request->validate([
            'closing_cash' => 'required|numeric|min:0|max:999999999999.99',
            'reason' => 'required|string|min:5|max:1000',
        ]);

        return $this->completeClose(
            $request,
            $shift,
            (float) $validated['closing_cash'],
            trim($validated['reason']),
            true,
        );
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

    private function completeClose(
        Request $request,
        Shift $shift,
        float $closingCash,
        ?string $note,
        bool $emergency,
    ) {
        $closedShift = DB::transaction(function () use (
            $request,
            $shift,
            $closingCash,
            $note,
            $emergency,
        ) {
            $locked = Shift::query()->lockForUpdate()->findOrFail($shift->id);
            if ($locked->status !== 'open') {
                throw ValidationException::withMessages(['shift' => 'Sesi kas ini sudah ditutup.']);
            }

            $summary = $this->cashLedger->summary($locked);
            $difference = round($closingCash - (float) $summary['cash_on_hand'], 2);
            if (! $emergency && abs($difference) > 0.009 && blank($note)) {
                throw ValidationException::withMessages([
                    'note' => 'Jelaskan selisih antara uang fisik dan total tunai di kasir.',
                ]);
            }

            $locked->update([
                'closed_by' => $request->user()->id,
                'ended_at' => now(),
                'closing_cash' => $closingCash,
                'status' => 'closed',
            ]);
            if (filled($note)) {
                $locked->movements()->create([
                    'outlet_id' => $locked->outlet_id,
                    'user_id' => $request->user()->id,
                    'type' => 'closing_note',
                    'category' => $emergency ? 'emergency_cash_close' : 'cash_reconciliation',
                    'amount' => 0,
                    'note' => trim($note),
                    'source_key' => "closing:{$locked->id}",
                    'occurred_at' => now(),
                    'meta' => [
                        'difference' => $difference,
                        'emergency' => $emergency,
                        'opened_by' => $locked->opened_by,
                        'closed_by' => $request->user()->id,
                    ],
                ]);
            }

            return $locked;
        });

        $this->cashLedger->broadcastShiftUpdate(
            (int) $closedShift->outlet_id,
            (int) $closedShift->id,
            $emergency ? 'emergency_closed' : 'closed',
            (int) $request->user()->id,
        );

        return response()->json([
            'message' => $emergency
                ? 'Sesi kas berhasil ditutup secara darurat.'
                : 'Sesi kas berhasil ditutup.',
            'data' => $this->serializeShift($closedShift->fresh()->load([
                'openedBy:id,name',
                'closedBy:id,name',
                'movements.user:id,name',
            ])),
        ]);
    }

    private function ensureCashOperator(Request $request): void
    {
        abort_if($this->isManager($request), 403, 'Admin dan owner hanya dapat memantau Uang Kas.');
        abort_unless(
            $this->isCashOperator($request),
            403,
            'Hanya kasir yang dapat mengoperasikan Uang Kas.',
        );
    }

    private function isCashOperator(Request $request): bool
    {
        return $this->roleSlugs($request)->contains('cashier');
    }

    private function isManager(Request $request): bool
    {
        return $this->roleSlugs($request)
            ->contains(fn ($role) => in_array($role, ['owner', 'admin'], true));
    }

    private function roleSlugs(Request $request)
    {
        return collect([$request->user()->role])
            ->merge($request->user()->roles()->pluck('slug'))
            ->filter()
            ->map(fn ($role) => strtolower(str_replace(['-', ' '], '_', trim((string) $role))))
            ->unique();
    }
}
