<?php

namespace App\Domains\Sales\Services;

use Illuminate\Support\Facades\DB;
use App\Domains\Sales\DTOs\OrderData;
use App\Domains\Sales\Repositories\OrderRepository;
use App\Models\KitchenTicket;

class OrderService
{
    public function __construct(
        private OrderRepository $repository
    ) {}

    public function placeOrder(OrderData $data)
    {
        return DB::transaction(function () use ($data) {
            $order = $this->repository->createOrder($data);

            $this->createKitchenTickets($order);

            return $order->load(['items', 'payments', 'kitchenTickets.items']);
        });
    }

    private function createKitchenTickets($order): void
    {
        $itemsByStation = $order->items->groupBy(fn ($item) => $item->station ?: 'kitchen');

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
        }
    }
}
