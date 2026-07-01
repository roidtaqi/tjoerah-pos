<?php

namespace App\Domains\Sales\DTOs;

class OrderData
{
    public function __construct(
        public readonly int $outletId,
        public readonly ?int $userId,
        public readonly array $items,
        public readonly float $subtotal,
        public readonly float $tax,
        public readonly float $total,
        public readonly string $paymentMethod,
        public readonly string $receiptNumber,
        public readonly string $orderType = 'take_away',
        public readonly ?int $customerId = null,
        public readonly ?int $tableId = null,
        public readonly float $discountTotal = 0,
        public readonly float $serviceCharge = 0,
        public readonly array $meta = [],
    ) {}
}
