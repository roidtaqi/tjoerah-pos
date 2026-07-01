<?php

namespace App\Domains\Sales\Events;

use App\Domains\POS\Models\Order;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class OrderCompleted
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public Order $order
    ) {}
}
