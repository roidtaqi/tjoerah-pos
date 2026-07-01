<?php

namespace App\Domains\CRM\Services;

use App\Domains\CRM\Models\LoyaltyPoint;
use Illuminate\Support\Facades\DB;

class LoyaltyService
{
    /**
     * Get the current points balance of a customer.
     */
    public static function getCustomerPointsBalance(int $customerId): int
    {
        return (int) LoyaltyPoint::where('customer_id', $customerId)->sum('points');
    }

    /**
     * Credit loyalty points to a customer.
     */
    public static function earnPoints(
        int $customerId,
        int $points,
        ?string $refType = null,
        ?string $refId = null,
        ?int $outletId = null,
        ?string $notes = null
    ): LoyaltyPoint {
        return LoyaltyPoint::create([
            'customer_id' => $customerId,
            'outlet_id' => $outletId,
            'points' => abs($points),
            'transaction_type' => 'earn',
            'reference_type' => $refType,
            'reference_id' => $refId,
            'notes' => $notes,
        ]);
    }

    /**
     * Redeem loyalty points from a customer.
     */
    public static function redeemPoints(
        int $customerId,
        int $points,
        ?string $refType = null,
        ?string $refId = null,
        ?int $outletId = null,
        ?string $notes = null
    ): ?LoyaltyPoint {
        return DB::transaction(function () use ($customerId, $points, $refType, $refId, $outletId, $notes) {
            $balance = self::getCustomerPointsBalance($customerId);
            if ($balance < $points) {
                return null; // Insufficient balance
            }

            return LoyaltyPoint::create([
                'customer_id' => $customerId,
                'outlet_id' => $outletId,
                'points' => -1 * abs($points),
                'transaction_type' => 'redeem',
                'reference_type' => $refType,
                'reference_id' => $refId,
                'notes' => $notes,
            ]);
        });
    }
}
