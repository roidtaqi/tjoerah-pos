<?php

namespace App\Domains\Sales\Events;

use App\Domains\Sales\Models\Order;
use App\Domains\KDS\Models\KitchenTicket;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class OrderCreated implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $tickets;

    public function __construct($tickets)
    {
        $this->tickets = $tickets;
    }

    public function broadcastOn()
    {
        return new Channel('kds.tickets');
    }

    public function broadcastWith()
    {
        // Broadcast new tickets generated from the order
        return [
            'tickets' => $this->tickets,
        ];
    }
}
