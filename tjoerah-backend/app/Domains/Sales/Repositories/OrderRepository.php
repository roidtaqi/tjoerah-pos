<?php

namespace App\Domains\Sales\Repositories;

use App\Domains\Core\Models\Outlet;
use App\Domains\CRM\Models\Customer;
use App\Domains\POS\Models\Order;
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
            'tax_rate' => $data->taxRate,
            'service_charge' => $data->serviceCharge,
            'total' => $data->total,
            'status' => $data->isOpenBill ? 'open' : 'paid',
            'submitted_at' => now(),
            'completed_at' => $data->isOpenBill ? null : now(),
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
                'submission_batch' => 1,
                'submitted_at' => now(),
            ]);
        }

        if (! $data->isOpenBill) {
            $order->payments()->create([
                'method' => $data->paymentMethod,
                'amount' => $data->total,
                'status' => 'completed',
                'paid_at' => now(),
            ]);
        }

        if (! $data->isOpenBill && $data->customerId) {
            $customer = Customer::lockForUpdate()->find($data->customerId);
            if ($customer) {
                $customer->total_spent = (float) $customer->total_spent + $data->total;
                $customer->visit_count = (int) $customer->visit_count + 1;
                $customer->last_purchase_at = now();
                $customer->save();
            }
        }

        return $order->load(['items', 'payments']);
    }
}
