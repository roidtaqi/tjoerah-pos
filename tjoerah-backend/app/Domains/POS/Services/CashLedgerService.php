<?php

namespace App\Domains\POS\Services;

use App\Domains\Employee\Models\Shift;
use App\Domains\POS\Models\CashMovement;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\Refund;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class CashLedgerService
{
    public function currentShift(int $outletId, int $userId): ?Shift
    {
        return Shift::query()
            ->where('outlet_id', $outletId)
            ->where('opened_by', $userId)
            ->where('status', 'open')
            ->latest('started_at')
            ->first();
    }

    /** @return array{shift: Shift, existing: bool} */
    public function openShift(
        int $outletId,
        int $userId,
        float $openingCash,
        ?int $employeeId = null,
        ?string $shiftNumber = null,
    ): array {
        return DB::transaction(function () use (
            $outletId,
            $userId,
            $openingCash,
            $employeeId,
            $shiftNumber,
        ) {
            $existing = Shift::query()
                ->where('outlet_id', $outletId)
                ->where('opened_by', $userId)
                ->where('status', 'open')
                ->lockForUpdate()
                ->latest('started_at')
                ->first();
            if ($existing) {
                return ['shift' => $existing, 'existing' => true];
            }

            $shift = Shift::create([
                'outlet_id' => $outletId,
                'employee_id' => $employeeId,
                'opened_by' => $userId,
                'shift_number' => $shiftNumber ?: 'KAS-'.now()->format('Ymd-His').'-'.$userId,
                'started_at' => now(),
                'opening_cash' => $openingCash,
                'status' => 'open',
            ]);
            $this->createMovement([
                'outlet_id' => $outletId,
                'shift_id' => $shift->id,
                'user_id' => $userId,
                'type' => 'opening',
                'category' => 'opening_cash',
                'amount' => $openingCash,
                'note' => 'Saldo awal kas',
                'source_key' => "opening:{$shift->id}",
                'occurred_at' => now(),
            ]);

            return ['shift' => $shift, 'existing' => false];
        });
    }

    public function createManualMovement(
        Shift $shift,
        int $userId,
        string $type,
        string $category,
        float $amount,
        string $note,
        ?string $evidencePath = null,
        ?string $clientReference = null,
    ): CashMovement {
        return $this->createMovement([
            'outlet_id' => $shift->outlet_id,
            'shift_id' => $shift->id,
            'user_id' => $userId,
            'type' => $type,
            'category' => $category,
            'amount' => $amount,
            'note' => $note,
            'evidence_path' => $evidencePath,
            'source_key' => 'manual:'.($clientReference ?: Str::uuid()),
            'occurred_at' => now(),
        ]);
    }

    public function recordPaidOrder(Order $order): ?CashMovement
    {
        $order->loadMissing('payments');
        $cashAmount = (float) $order->payments
            ->where('status', 'completed')
            ->filter(fn ($payment) => $this->isCashMethod($payment->method))
            ->sum('amount');
        if ($cashAmount <= 0.009) {
            return null;
        }

        $meta = $order->meta ?? [];
        $userId = (int) ($meta['cashier_user_id'] ?? $order->user_id ?? 0);
        if ($userId <= 0) {
            return null;
        }
        $shift = $this->shiftForOrder($order, $userId);

        return $this->createMovement([
            'outlet_id' => $order->outlet_id,
            'shift_id' => $shift->id,
            'user_id' => $userId,
            'type' => 'sale',
            'category' => 'cash_sale',
            'amount' => $cashAmount,
            'note' => "Penjualan {$order->receipt_number}",
            'reference_type' => Order::class,
            'reference_id' => $order->id,
            'reference_number' => $order->receipt_number,
            'source_key' => "sale:{$order->id}",
            'occurred_at' => $order->completed_at ?? now(),
            'meta' => [
                'order_total' => (float) $order->total,
                'payment_methods' => $order->payments->pluck('method')->values()->all(),
            ],
        ]);
    }

    public function recordRefund(
        Refund $refund,
        Order $order,
        ?string $requestedMethod = null,
    ): ?CashMovement {
        $order->loadMissing('payments');
        $method = $this->resolveRefundMethod($order, $refund->payment_id, $requestedMethod);
        $cashAmount = 0.0;
        if ($this->isCashMethod($method)) {
            $cashAmount = (float) $refund->amount;
        } elseif ($method === 'mixed') {
            $originalCash = (float) $order->payments
                ->where('status', 'completed')
                ->filter(fn ($payment) => $this->isCashMethod($payment->method))
                ->sum('amount');
            $previousCashRefunds = (float) Refund::query()
                ->where('order_id', $order->id)
                ->where('status', 'approved')
                ->whereKeyNot($refund->id)
                ->get()
                ->sum(fn (Refund $item) => (float) data_get($item->meta, 'cash_amount', 0));
            $cashAmount = min((float) $refund->amount, max($originalCash - $previousCashRefunds, 0));
        }

        $refundMeta = $refund->meta ?? [];
        $refundMeta['cash_amount'] = $cashAmount;
        $refund->update(['method' => $method, 'meta' => $refundMeta]);
        if ($cashAmount <= 0.009) {
            return null;
        }

        $userId = (int) ($refund->user_id ?: $order->user_id);
        if ($userId <= 0) {
            return null;
        }
        $shift = $this->currentShift($order->outlet_id, $userId)
            ?? $this->openShift($order->outlet_id, $userId, 0)['shift'];

        return $this->createMovement([
            'outlet_id' => $order->outlet_id,
            'shift_id' => $shift->id,
            'user_id' => $userId,
            'type' => 'refund',
            'category' => 'customer_refund',
            'amount' => $cashAmount,
            'note' => $refund->reason,
            'reference_type' => Refund::class,
            'reference_id' => $refund->id,
            'reference_number' => $order->receipt_number,
            'source_key' => "refund:{$refund->id}",
            'occurred_at' => now(),
            'meta' => ['refund_method' => $method, 'refund_total' => (float) $refund->amount],
        ]);
    }

    /** @return array<string, float|int> */
    public function summary(Shift $shift): array
    {
        $movements = $shift->relationLoaded('movements')
            ? $shift->movements
            : $shift->movements()->get();
        $sum = fn (array $types) => (float) $movements
            ->whereIn('type', $types)
            ->sum('amount');
        $cashFundBalance = round(
            $sum(['opening', 'cash_in', 'adjustment_in'])
                - $sum(['cash_out', 'adjustment_out']),
            2,
        );
        $cashOnHand = round(
            $cashFundBalance + $sum(['sale']) - $sum(['refund']),
            2,
        );

        return [
            'movement_count' => $movements->count(),
            'opening_cash' => $sum(['opening']),
            'cash_sales' => $sum(['sale']),
            'manual_cash_in' => $sum(['cash_in']),
            'cash_refunds' => $sum(['refund']),
            'manual_cash_out' => $sum(['cash_out']),
            'adjustments_in' => $sum(['adjustment_in']),
            'adjustments_out' => $sum(['adjustment_out']),
            'cash_fund_balance' => $cashFundBalance,
            'cash_on_hand' => $cashOnHand,
            // Kept for older app versions that still read expected_cash.
            'expected_cash' => $cashOnHand,
            'closing_cash' => $shift->closing_cash === null ? null : (float) $shift->closing_cash,
            'difference' => $shift->closing_cash === null
                ? null
                : round((float) $shift->closing_cash - $cashOnHand, 2),
        ];
    }

    private function shiftForOrder(Order $order, int $userId): Shift
    {
        $requestedId = data_get($order->meta, 'cash_shift_id');
        if ($requestedId) {
            $requested = Shift::query()
                ->whereKey($requestedId)
                ->where('outlet_id', $order->outlet_id)
                ->where('status', 'open')
                ->first();
            if ($requested) {
                return $requested;
            }
        }

        return $this->currentShift($order->outlet_id, $userId)
            ?? $this->openShift($order->outlet_id, $userId, 0)['shift'];
    }

    private function resolveRefundMethod(Order $order, ?string $paymentId, ?string $requested): string
    {
        if ($requested) {
            return $this->normalizeMethod($requested);
        }
        if ($paymentId) {
            $payment = $order->payments->firstWhere('id', $paymentId);
            if ($payment) {
                return $this->normalizeMethod($payment->method);
            }
        }
        $methods = $order->payments
            ->where('status', 'completed')
            ->pluck('method')
            ->map(fn ($method) => $this->normalizeMethod($method))
            ->unique()
            ->values();

        return $methods->count() === 1 ? (string) $methods->first() : 'mixed';
    }

    private function isCashMethod(?string $method): bool
    {
        return in_array($this->normalizeMethod($method), ['cash'], true);
    }

    private function normalizeMethod(?string $method): string
    {
        $normalized = strtolower(trim((string) $method));

        return match ($normalized) {
            'tunai', 'cash' => 'cash',
            'card', 'debit', 'debit card', 'debit_card' => 'debit_card',
            default => $normalized ?: 'unknown',
        };
    }

    private function createMovement(array $attributes): CashMovement
    {
        $sourceKey = $attributes['source_key'] ?? null;
        if ($sourceKey) {
            return CashMovement::firstOrCreate(['source_key' => $sourceKey], $attributes);
        }

        return CashMovement::create($attributes);
    }
}
