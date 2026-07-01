<?php

namespace App\Domains\Sales\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\Refund;
use App\Domains\POS\Models\VoidTransaction;
use App\Domains\Sales\Services\OrderService;
use App\Domains\Sales\DTOs\OrderData;

class OrderController extends Controller
{
    public function __construct(
        private OrderService $orderService
    ) {}

    public function store(Request $request)
    {
        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'customer_id' => 'nullable|integer|exists:customers,id',
            'table_id' => 'nullable|integer|exists:tables,id',
            'order_type' => 'nullable|string|in:dine_in,take_away,delivery',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|integer|exists:products,id',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.snapshot_name' => 'required|string',
            'items.*.snapshot_price' => 'required|numeric',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.total' => 'required|numeric',
            'items.*.station' => 'nullable|string',
            'items.*.modifiers' => 'nullable|array',
            'items.*.notes' => 'nullable|string',
            'subtotal' => 'required|numeric',
            'discount_total' => 'nullable|numeric',
            'tax' => 'required|numeric',
            'service_charge' => 'nullable|numeric',
            'total' => 'required|numeric',
            'payment_method' => 'required|string',
            'receipt_number' => 'required|string|unique:orders,receipt_number',
            'meta' => 'nullable|array',
        ]);

        $dto = new OrderData(
            outletId: $validated['outlet_id'],
            userId: $request->user()?->id,
            items: $validated['items'],
            subtotal: $validated['subtotal'],
            tax: $validated['tax'],
            total: $validated['total'],
            paymentMethod: $validated['payment_method'],
            receiptNumber: $validated['receipt_number'],
            orderType: $validated['order_type'] ?? 'take_away',
            customerId: $validated['customer_id'] ?? null,
            tableId: $validated['table_id'] ?? null,
            discountTotal: $validated['discount_total'] ?? 0,
            serviceCharge: $validated['service_charge'] ?? 0,
            meta: $validated['meta'] ?? [],
        );

        $order = $this->orderService->placeOrder($dto);

        return response()->json([
            'message' => 'Order placed successfully',
            'data' => $order
        ], 201);
    }

    public function show(Order $order)
    {
        return response()->json($order->load(['items', 'payments', 'kitchenTickets.items']));
    }

    public function hold(Order $order)
    {
        $order->update(['status' => 'held']);

        return response()->json(['message' => 'Order held.', 'data' => $order]);
    }

    public function resume(Order $order)
    {
        $order->update(['status' => 'draft']);

        return response()->json(['message' => 'Order resumed.', 'data' => $order]);
    }

    public function complete(Order $order)
    {
        $order->update(['status' => 'completed', 'completed_at' => now()]);

        return response()->json(['message' => 'Order completed.', 'data' => $order]);
    }

    public function void(Request $request, Order $order)
    {
        $validated = $request->validate([
            'order_item_id' => 'nullable|integer|exists:order_items,id',
            'amount' => 'nullable|numeric',
            'reason' => 'required|string',
        ]);

        $void = VoidTransaction::create([
            'order_id' => $order->id,
            'order_item_id' => $validated['order_item_id'] ?? null,
            'user_id' => $request->user()?->id,
            'amount' => $validated['amount'] ?? $order->total,
            'reason' => $validated['reason'],
        ]);

        $order->update(['status' => 'voided']);

        return response()->json(['message' => 'Order voided.', 'data' => $void], 201);
    }

    public function refund(Request $request, Order $order)
    {
        $validated = $request->validate([
            'payment_id' => 'nullable|integer|exists:payments,id',
            'amount' => 'required|numeric|min:0',
            'type' => 'nullable|string|in:full,partial',
            'reason' => 'required|string',
        ]);

        $refund = Refund::create([
            'order_id' => $order->id,
            'payment_id' => $validated['payment_id'] ?? null,
            'user_id' => $request->user()?->id,
            'amount' => $validated['amount'],
            'type' => $validated['type'] ?? 'full',
            'reason' => $validated['reason'],
            'status' => 'approved',
        ]);

        $order->update(['status' => 'refunded']);

        return response()->json(['message' => 'Refund recorded.', 'data' => $refund], 201);
    }
}
