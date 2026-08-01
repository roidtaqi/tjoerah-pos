<?php

namespace App\Domains\Sales\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
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
        return collect($this->tickets)
            ->pluck('outlet_id')
            ->filter()
            ->unique()
            ->map(fn ($outletId) => new PrivateChannel("kds.outlet.{$outletId}"))
            ->all();
    }

    public function broadcastAs(): string
    {
        return 'order.created';
    }

    public function broadcastWith()
    {
        return [
            'tickets' => collect($this->tickets)
                ->map(fn ($ticket) => $ticket->loadMissing('items')->toArray())
                ->values()
                ->all(),
        ];
    }
}
