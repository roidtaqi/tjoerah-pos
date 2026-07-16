<?php

namespace App\Domains\Sales\Services;

use App\Domains\KDS\Models\KitchenTicket;
use App\Domains\Sales\DTOs\OrderData;
use App\Domains\Sales\Events\OrderCompleted;
use App\Domains\Sales\Events\OrderCreated;
use App\Domains\Sales\Repositories\OrderRepository;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
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

        $this->dispatchSideEffects($order, $tickets);

        return $order->load(['items', 'payments', 'kitchenTickets.items']);
    }

    private function dispatchSideEffects($order, $tickets): void
    {
        try {
            OrderCompleted::dispatch($order);
        } catch (Throwable $exception) {
            Log::warning('Order follow-up jobs could not be dispatched.', [
                'order_id' => $order->id,
                'error' => $exception->getMessage(),
            ]);
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

    private function createKitchenTickets($order)
    {
        $itemsByStation = $order->items->groupBy(fn ($item) => $item->station ?: 'kitchen');
        $tickets = collect();

        foreach ($itemsByStation as $station => $items) {
            $ticket = KitchenTicket::create([
                'order_id' => $order->id,
                'outlet_id' => $order->outlet_id,
                'station' => $station,
                'status' => 'pending',
                'priority' => $order->meta['priority'] ?? 'normal',
            ]);

            foreach ($items as $item) {
                $ticket->items()->create([
                    'order_item_id' => $item->id,
                    'name' => $item->snapshot_name,
                    'qty' => $item->qty,
                    'modifiers' => $item->modifiers,
                    'notes' => $item->notes,
                    'status' => 'pending',
                ]);
            }
            $tickets->push($ticket->load('items'));
        }

        return $tickets;
    }
}
