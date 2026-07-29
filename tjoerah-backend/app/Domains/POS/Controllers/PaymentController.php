<?php

namespace App\Domains\POS\Controllers;

use App\Domains\CRM\Models\Customer;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\Payment;
use App\Domains\Sales\Events\OrderCompleted;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PaymentController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate([
            'order_id' => 'required|uuid|exists:orders,id',
            'method' => 'required|string|max:100',
            'amount' => 'required|numeric|min:0',
            'reference_number' => 'nullable|string|max:255',
            'meta' => 'nullable|array',
        ]);
        $order = Order::findOrFail($validated['order_id']);
        $this->ensureOrderIsAccessible($request, $order);
        if (in_array($order->status, ['open', 'held'], true)) {
            throw ValidationException::withMessages([
                'order_id' => 'Bayar open bill melalui endpoint pembayaran open bill.',
            ]);
        }

        $payment = Payment::create([
            ...$validated,
            'status' => 'completed',
            'paid_at' => now(),
        ]);

        if ($order->payments()->sum('amount') >= $order->total) {
            $order->update(['status' => 'paid', 'completed_at' => $order->completed_at ?? now()]);
        }

        return response()->json($payment, 201);
    }

    public function pay(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);
        $validated = $request->validate([
            'method' => 'required|string|max:100',
            'payment_breakdown' => 'nullable|array',
            'payment_breakdown.*' => 'numeric|min:0',
            'amount_received' => 'nullable|numeric|min:0',
            'change' => 'nullable|numeric|min:0',
            'reference_number' => 'nullable|string|max:255',
        ]);

        [$paidOrder, $wasPaidNow] = DB::transaction(function () use ($order, $validated) {
            $locked = Order::lockForUpdate()->findOrFail($order->id);
            if ($locked->status === 'paid') {
                return [$locked, false];
            }
            if (! in_array($locked->status, ['open', 'held'], true)) {
                throw ValidationException::withMessages([
                    'order' => 'Hanya open bill yang dapat dibayar dari tindakan ini.',
                ]);
            }

            $paidAmount = (float) $locked->total;
            $breakdown = collect($validated['payment_breakdown'] ?? [])
                ->map(fn ($amount) => (float) $amount)
                ->all();
            if ($breakdown && abs(array_sum($breakdown) - $paidAmount) > 0.01) {
                throw ValidationException::withMessages([
                    'payment_breakdown' => 'Rincian pembayaran harus sama dengan total tagihan.',
                ]);
            }

            $locked->payments()->create([
                'method' => $validated['method'],
                'amount' => $paidAmount,
                'status' => 'completed',
                'reference_number' => $validated['reference_number'] ?? null,
                'meta' => [
                    'payment_breakdown' => $breakdown,
                    'amount_received' => $validated['amount_received'] ?? null,
                    'change' => $validated['change'] ?? 0,
                ],
                'paid_at' => now(),
            ]);

            $meta = $locked->meta ?? [];
            $meta['payment_breakdown'] = $breakdown;
            $meta['amount_received'] = $validated['amount_received'] ?? null;
            $meta['change'] = $validated['change'] ?? 0;
            $locked->update([
                'status' => 'paid',
                'completed_at' => now(),
                'meta' => $meta,
            ]);

            if ($locked->customer_id) {
                $customer = Customer::lockForUpdate()->find($locked->customer_id);
                if ($customer) {
                    $customer->total_spent = (float) $customer->total_spent + $paidAmount;
                    $customer->visit_count = (int) $customer->visit_count + 1;
                    $customer->last_purchase_at = now();
                    $customer->save();
                }
            }

            return [$locked, true];
        });

        if ($wasPaidNow) {
            OrderCompleted::dispatch($paidOrder);
        }

        return response()->json([
            'message' => $wasPaidNow
                ? 'Open bill berhasil dibayar.'
                : 'Open bill ini sudah dibayar.',
            'data' => $paidOrder->load(['items', 'payments', 'refunds', 'kitchenTickets.items']),
        ], $wasPaidNow ? 201 : 200);
    }

    private function ensureOrderIsAccessible(Request $request, Order $order): void
    {
        $order->loadMissing('outlet');
        $companyId = $request->user()?->company_id;
        abort_if(
            $companyId && (int) $order->outlet?->company_id !== (int) $companyId,
            404,
        );
    }
}
