<?php

namespace App\Domains\POS\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class CashShiftUpdated implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public int $outletId,
        public ?int $shiftId,
        public string $action,
        public ?int $actorId,
    ) {}

    public function broadcastOn(): PrivateChannel
    {
        return new PrivateChannel("cash.outlet.{$this->outletId}");
    }

    public function broadcastAs(): string
    {
        return 'cash.shift.updated';
    }

    /** @return array<string, int|string|null> */
    public function broadcastWith(): array
    {
        return [
            'outlet_id' => $this->outletId,
            'shift_id' => $this->shiftId,
            'action' => $this->action,
            'actor_id' => $this->actorId,
            'occurred_at' => now()->toIso8601String(),
        ];
    }
}
