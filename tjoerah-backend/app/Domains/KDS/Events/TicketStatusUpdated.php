<?php

namespace App\Domains\KDS\Events;

use App\Domains\KDS\Models\KitchenTicket;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
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
        return new PrivateChannel("kds.outlet.{$this->ticket->outlet_id}");
    }

    public function broadcastAs(): string
    {
        return 'ticket.status.updated';
    }

    public function broadcastWith()
    {
        return [
            'ticket' => $this->ticket->load('items')->toArray(),
        ];
    }
}
