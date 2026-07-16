<?php

namespace App\Domains\KDS\Events;

use App\Domains\KDS\Models\KitchenTicket;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class TicketStatusUpdated implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public KitchenTicket $ticket;

    public function __construct(KitchenTicket $ticket)
    {
        $this->ticket = $ticket;
    }

    public function broadcastOn()
    {
        return new Channel('kds.tickets');
    }

    public function broadcastWith()
    {
        return [
            'ticket' => $this->ticket->load('items')->toArray(),
        ];
    }
}
