<?php

namespace App\Domains\Sales\Repositories;

use App\Models\Order;
use App\Models\Outlet;
use App\Domains\Sales\DTOs\OrderData;

class OrderRepository
{
    public function createOrder(OrderData $data)
    {
        $outlet = Outlet::find($data->outletId);

        $order = Order::create([
            'company_id' => $outlet?->company_id,
            'brand_id' => $outlet?->brand_id,
            'outlet_id' => $data->outletId,
            'user_id' => $data->userId,
            'customer_id' => $data->customerId,
            'table_id' => $data->tableId,
            'receipt_number' => $data->receiptNumber,
            'order_number' => $data->receiptNumber,
            'order_type' => $data->orderType,
            'subtotal' => $data->subtotal,
            'discount_total' => $data->discountTotal,
            'tax' => $data->tax,
            'service_charge' => $data->serviceCharge,
            'total' => $data->total,
            'status' => 'paid',
            'completed_at' => now(),
            'meta' => $data->meta,
        ]);

        foreach ($data->items as $item) {
            $order->items()->create([
                'product_id' => $item['product_id'],
                'product_variant_id' => $item['product_variant_id'] ?? null,
                'snapshot_name' => $item['snapshot_name'],
                'snapshot_price' => $item['snapshot_price'],
                'qty' => $item['qty'],
                'discount_total' => $item['discount_total'] ?? 0,
                'total' => $item['total'],
                'station' => $item['station'] ?? null,
                'modifiers' => $item['modifiers'] ?? null,
                'notes' => $item['notes'] ?? null,
            ]);
        }

        $order->payments()->create([
            'method' => $data->paymentMethod,
            'amount' => $data->total,
            'status' => 'completed',
            'paid_at' => now(),
        ]);

        return $order->load(['items', 'payments']);
    }
}
