<?php

namespace App\Domains\Sales\Services;

use App\Domains\KDS\Models\KitchenTicket;
use App\Domains\POS\Models\Order;
use App\Domains\Sales\DTOs\OrderData;
use App\Domains\Sales\Events\OrderCompleted;
use App\Domains\Sales\Events\OrderCreated;
use App\Domains\Sales\Events\OrderSubmitted;
use App\Domains\Sales\Repositories\OrderRepository;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Throwable;

class OrderService
{
    public function __construct(
        private OrderRepository $repository
    ) {}

    public function placeOrder(OrderData $data)
    {
        [$order, $tickets] = DB::transaction(function () use ($data) {
            $order = $this->repository->createOrder($data);
            $tickets = $this->createKitchenTickets($order);

            return [$order, $tickets];
        });

        $this->dispatchSideEffects($order, $tickets, $data->isOpenBill);

        return $order->load(['items', 'payments', 'kitchenTickets.items']);
    }

    public function appendOpenBill(Order $order, array $items, string $clientAppendId): array
    {
        [$updatedOrder, $tickets, $batch, $duplicate] = DB::transaction(
            function () use ($order, $items, $clientAppendId) {
                $lockedOrder = Order::query()->lockForUpdate()->findOrFail($order->id);
                if (! in_array($lockedOrder->status, ['open', 'held'], true)) {
                    throw ValidationException::withMessages([
                        'order' => 'Hanya open bill yang belum dibayar yang dapat ditambah.',
                    ]);
                }

                $meta = $lockedOrder->meta ?? [];
                $appendBatches = collect($meta['append_batches'] ?? []);
                $existingBatch = $appendBatches->firstWhere('client_append_id', $clientAppendId);
                if ($existingBatch) {
                    return [
                        $lockedOrder->load(['items', 'payments', 'kitchenTickets.items']),
                        collect(),
                        (int) ($existingBatch['batch'] ?? 1),
                        true,
                    ];
                }

                $batch = ((int) $lockedOrder->items()->max('submission_batch')) + 1;
                $submittedAt = now();
                foreach ($items as $item) {
                    $lockedOrder->items()->create([
                        'product_id' => $item['product_id'],
                        'product_variant_id' => $item['product_variant_id'] ?? null,
                        'snapshot_name' => $item['snapshot_name'],
                        'snapshot_price' => $item['snapshot_price'],
                        'qty' => $item['qty'],
                        'discount_total' => $item['discount_total'] ?? 0,
                        'total' => $item['total'],
                        'station' => $item['station'] ?? null,
                        'modifiers' => $item['modifiers'] ?? null,
                        'notes' => $item['notes'] ?? null,
                        'submission_batch' => $batch,
                        'submitted_at' => $submittedAt,
                    ]);
                }

                $newSubtotal = round((float) $lockedOrder->items()->sum('total'), 2);
                $discountRate = (float) $lockedOrder->subtotal > 0
                    ? (float) $lockedOrder->discount_total / (float) $lockedOrder->subtotal
                    : 0.0;
                $discount = round(min($newSubtotal * $discountRate, $newSubtotal), 2);
                $tax = round(
                    max($newSubtotal - $discount, 0) * ((float) $lockedOrder->tax_rate / 100),
                    2,
                );
                $total = round(
                    $newSubtotal - $discount + $tax + (float) $lockedOrder->service_charge,
                    2,
                );
                $appendBatches->push([
                    'client_append_id' => $clientAppendId,
                    'batch' => $batch,
                    'submitted_at' => $submittedAt->toIso8601String(),
                    'item_count' => count($items),
                ]);
                $meta['append_batches'] = $appendBatches->values()->all();
                $lockedOrder->update([
                    'subtotal' => $newSubtotal,
                    'discount_total' => $discount,
                    'tax' => $tax,
                    'total' => $total,
                    'meta' => $meta,
                ]);

                $newItems = $lockedOrder->items()
                    ->where('submission_batch', $batch)
                    ->get();
                $tickets = $this->createKitchenTickets($lockedOrder, $newItems);

                return [$lockedOrder, $tickets, $batch, false];
            },
        );

        if (! $duplicate) {
            $this->dispatchSideEffects($updatedOrder, $tickets, true);
        }

        return [
            'order' => $updatedOrder->fresh()->load([
                'items',
                'payments',
                'kitchenTickets.items',
            ]),
            'batch' => $batch,
            'duplicate' => $duplicate,
        ];
    }

    private function dispatchSideEffects($order, $tickets, bool $isOpenBill): void
    {
        try {
            OrderSubmitted::dispatch($order);
        } catch (Throwable $exception) {
            Log::warning('Order follow-up jobs could not be dispatched.', [
                'order_id' => $order->id,
                'error' => $exception->getMessage(),
            ]);
        }

        if (! $isOpenBill) {
            try {
                OrderCompleted::dispatch($order);
            } catch (Throwable $exception) {
                Log::warning('Paid order follow-up jobs could not be dispatched.', [
                    'order_id' => $order->id,
                    'error' => $exception->getMessage(),
                ]);
            }
        }

        try {
            OrderCreated::dispatch($tickets);
        } catch (Throwable $exception) {
            // Realtime delivery must never roll back or reject a paid order.
            Log::warning('KDS realtime notification could not be delivered.', [
                'order_id' => $order->id,
                'error' => $exception->getMessage(),
            ]);
        }
    }

    private function createKitchenTickets($order, $items = null)
    {
        $order->loadMissing('outlet');
        $automatic = ($order->outlet?->kds_mode ?? 'manual') === 'automatic';
        $itemsByStation = ($items ?? $order->items)
            ->groupBy(fn ($item) => $item->station ?: 'kitchen');
        $tickets = collect();

        foreach ($itemsByStation as $station => $items) {
            $ticket = KitchenTicket::create([
                'order_id' => $order->id,
                'outlet_id' => $order->outlet_id,
                'station' => $station,
                'status' => $automatic ? 'completed' : 'pending',
                'priority' => $order->meta['priority'] ?? 'normal',
                'accepted_at' => $automatic ? now() : null,
                'preparing_at' => $automatic ? now() : null,
                'ready_at' => $automatic ? now() : null,
                'completed_at' => $automatic ? now() : null,
            ]);

            foreach ($items as $item) {
                $ticket->items()->create([
                    'order_item_id' => $item->id,
                    'name' => $item->snapshot_name,
                    'qty' => $item->qty,
                    'modifiers' => $item->modifiers,
                    'notes' => $item->notes,
                    'status' => $automatic ? 'completed' : 'pending',
                ]);
            }
            $tickets->push($ticket->load('items'));
        }

        return $tickets;
    }
}
