<?php

namespace App\Domains\CRM\Listeners;

use App\Domains\Sales\Events\OrderCompleted;
use App\Domains\CRM\Services\LoyaltyService;
use Illuminate\Contracts\Queue\ShouldQueue;

class AwardLoyaltyPointsListener implements ShouldQueue
{
    /**
     * Handle the event.
     */
    public function handle(OrderCompleted $event): void
    {
        $order = $event->order;

        if (!$order->customer_id) {
            return; // No customer associated with the order
        }

        // Earn 1 point for every Rp 10.000 spent
        $pointsEarned = (int) floor((float) $order->total / 10000);

        if ($pointsEarned > 0) {
            LoyaltyService::earnPoints(
                customerId: $order->customer_id,
                points: $pointsEarned,
                refType: get_class($order),
                refId: $order->id,
                outletId: $order->outlet_id,
                notes: "Earned points from order {$order->receipt_number}"
            );
        }
    }
}
