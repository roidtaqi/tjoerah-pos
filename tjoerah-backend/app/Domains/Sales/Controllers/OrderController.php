<?php

namespace App\Domains\Sales\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Inventory\Services\ProductionIncidentService;
use App\Domains\KDS\Models\KitchenTicket;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\OrderItem;
use App\Domains\POS\Models\Refund;
use App\Domains\Sales\DTOs\OrderData;
use App\Domains\Sales\Services\OrderCancellationService;
use App\Domains\Sales\Services\OrderService;
use App\Http\Controllers\Controller;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class OrderController extends Controller
{
    public function __construct(
        private OrderService $orderService,
        private OrderCancellationService $orderCancellationService,
        private ProductionIncidentService $productionIncidentService,
    ) {}

    public function index(Request $request)
    {
        $request->validate([
            'per_page' => 'nullable|integer|min:1|max:100',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
            'status' => 'nullable|string|max:50',
            'q' => 'nullable|string|max:255',
            'created_from' => 'nullable|required_with:created_to|date',
            'created_to' => 'nullable|required_with:created_from|date|after:created_from',
            'include_open' => 'nullable|boolean',
        ]);

        $createdFrom = $request->filled('created_from')
            ? Carbon::parse($request->string('created_from')->toString())->utc()
            : null;
        $createdTo = $request->filled('created_to')
            ? Carbon::parse($request->string('created_to')->toString())->utc()
            : null;
        $includeOpen = $request->boolean('include_open');

        return Order::with(['items', 'payments', 'refunds'])
            ->when(
                $request->user()?->company_id,
                fn ($query, $companyId) => $query->whereHas(
                    'outlet',
                    fn ($outlet) => $outlet->where('company_id', $companyId),
                ),
            )
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($createdFrom || $createdTo, function ($query) use ($createdFrom, $createdTo, $includeOpen) {
                $query->where(function ($period) use ($createdFrom, $createdTo, $includeOpen) {
                    $period
                        ->when($createdFrom, fn ($range, $from) => $range->where('created_at', '>=', $from))
                        ->when($createdTo, fn ($range, $to) => $range->where('created_at', '<', $to));
                    if ($includeOpen) {
                        $period->orWhereIn('status', ['open', 'held']);
                    }
                });
            })
            ->when($request->string('status')->trim()->isNotEmpty(), fn ($query) => $query->where('status', $request->string('status')->trim()->toString()))
            ->when($request->string('q')->trim()->isNotEmpty(), function ($query) use ($request) {
                $term = $request->string('q')->trim()->toString();
                $query->where(fn ($search) => $search
                    ->where('receipt_number', 'like', "%{$term}%")
                    ->orWhereHas('items', fn ($items) => $items->where('snapshot_name', 'like', "%{$term}%")));
            })
            ->latest()
            ->paginate($request->integer('per_page', 100));
    }

    public function store(Request $request)
    {
        $existingOrder = $this->findExistingOrder($request);
        if ($existingOrder) {
            return response()->json([
                'message' => 'Order already received',
                'data' => $existingOrder->load(['items', 'payments', 'kitchenTickets.items']),
            ]);
        }

        $validated = $request->validate([
            'outlet_id' => 'required|integer|exists:outlets,id',
            'customer_id' => 'nullable|integer|exists:customers,id',
            'table_id' => 'nullable|integer|exists:tables,id',
            'order_type' => 'nullable|string|in:dine_in,take_away,delivery',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'nullable|integer|exists:products,id',
            'items.*.is_manual' => 'nullable|boolean',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.snapshot_name' => 'required|string|max:255',
            'items.*.snapshot_price' => 'required|numeric|min:0',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.total' => 'required|numeric|min:0',
            'items.*.station' => 'nullable|string|max:50',
            'items.*.modifiers' => 'nullable|array',
            'items.*.notes' => 'nullable|string',
            'subtotal' => 'required|numeric',
            'discount_total' => 'nullable|numeric|min:0',
            'tax' => 'nullable|numeric|min:0',
            'service_charge' => 'nullable|numeric|min:0',
            'total' => 'nullable|numeric|min:0',
            'is_open_bill' => 'nullable|boolean',
            'payment_method' => 'nullable|required_unless:is_open_bill,true|string',
            'receipt_number' => 'required|string|unique:orders,receipt_number',
            'meta' => 'nullable|array',
        ]);

        $validated['items'] = $this->normalizeOrderItems($validated['items']);
        $outlet = Outlet::findOrFail($validated['outlet_id']);
        $this->ensureOutletIsAccessible($request, $outlet);
        $subtotal = round(collect($validated['items'])->sum(
            fn (array $item) => (float) $item['total'],
        ), 2);
        $discount = min((float) ($validated['discount_total'] ?? 0), $subtotal);
        $serviceCharge = (float) ($validated['service_charge'] ?? 0);
        $taxRate = $outlet->tax_enabled ? (float) $outlet->tax_rate : 0.0;
        $tax = round(max($subtotal - $discount, 0) * ($taxRate / 100), 2);
        $total = round($subtotal - $discount + $tax + $serviceCharge, 2);
        $isOpenBill = (bool) ($validated['is_open_bill'] ?? false);
        $meta = $validated['meta'] ?? [];
        $paymentBreakdown = collect($meta['payment_breakdown'] ?? [])
            ->map(fn ($amount) => (float) $amount)
            ->filter(fn ($amount) => $amount > 0)
            ->all();
        if (! $isOpenBill && $paymentBreakdown && abs(array_sum($paymentBreakdown) - $total) > 0.01) {
            throw ValidationException::withMessages([
                'meta.payment_breakdown' => 'Rincian pembayaran harus sama dengan total tagihan.',
            ]);
        }
        if ($paymentBreakdown) {
            $meta['payment_breakdown'] = $paymentBreakdown;
        }
        $meta['tax_rate'] = $taxRate;

        $dto = new OrderData(
            outletId: $validated['outlet_id'],
            userId: $request->user()?->id,
            items: $validated['items'],
            subtotal: $subtotal,
            tax: $tax,
            total: $total,
            paymentMethod: $validated['payment_method'] ?? 'open_bill',
            receiptNumber: $validated['receipt_number'],
            orderType: $validated['order_type'] ?? 'take_away',
            customerId: $validated['customer_id'] ?? null,
            tableId: $validated['table_id'] ?? null,
            discountTotal: $discount,
            serviceCharge: $serviceCharge,
            meta: $meta,
            isOpenBill: $isOpenBill,
            taxRate: $taxRate,
        );

        $order = $this->orderService->placeOrder($dto);

        return response()->json([
            'message' => $isOpenBill
                ? 'Open bill berhasil disimpan dan dikirim ke dapur.'
                : 'Order placed successfully',
            'data' => $order,
        ], 201);
    }

    public function appendItems(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);
        $validated = $request->validate([
            'client_append_id' => 'required|string|max:100',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'nullable|integer|exists:products,id',
            'items.*.is_manual' => 'nullable|boolean',
            'items.*.product_variant_id' => 'nullable|integer|exists:product_variants,id',
            'items.*.snapshot_name' => 'required|string|max:255',
            'items.*.snapshot_price' => 'required|numeric|min:0',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.total' => 'required|numeric|min:0',
            'items.*.station' => 'nullable|string|max:50',
            'items.*.modifiers' => 'nullable|array',
            'items.*.notes' => 'nullable|string|max:1000',
        ]);

        $validated['items'] = $this->normalizeOrderItems($validated['items']);
        $result = $this->orderService->appendOpenBill(
            $order,
            $validated['items'],
            $validated['client_append_id'],
        );

        return response()->json([
            'message' => $result['duplicate']
                ? 'Tambahan open bill ini sudah diterima sebelumnya.'
                : 'Tambahan open bill berhasil disimpan.',
            'data' => $result['order'],
            'submission_batch' => $result['batch'],
        ], $result['duplicate'] ? 200 : 201);
    }

    private function normalizeOrderItems(array $items): array
    {
        return collect($items)->map(function (array $item, int $index) {
            $isManual = (bool) ($item['is_manual'] ?? false);
            if (! $isManual && empty($item['product_id'])) {
                throw ValidationException::withMessages([
                    "items.{$index}.product_id" => 'Produk wajib dipilih untuk item katalog.',
                ]);
            }

            if ($isManual) {
                $item['product_id'] = null;
                $item['product_variant_id'] = null;
                $item['station'] = 'cashier';
                $item['total'] = round(
                    (float) $item['snapshot_price'] * (int) $item['qty'],
                    2,
                );
                $item['modifiers'] = array_merge($item['modifiers'] ?? [], [
                    'manual_item' => true,
                ]);
            }

            unset($item['is_manual']);

            return $item;
        })->all();
    }

    private function findExistingOrder(Request $request): ?Order
    {
        $outletId = $request->integer('outlet_id');
        if (! $outletId) {
            return null;
        }

        $clientOrderId = $request->input('meta.client_order_id');
        if (is_string($clientOrderId) && $clientOrderId !== '') {
            $order = Order::where('outlet_id', $outletId)
                ->where('meta->client_order_id', $clientOrderId)
                ->first();
            if ($order) {
                return $order;
            }

            return null;
        }

        $receiptNumber = $request->string('receipt_number')->toString();
        if ($receiptNumber === '') {
            return null;
        }

        return Order::where('outlet_id', $outletId)
            ->where('receipt_number', $receiptNumber)
            ->first();
    }

    public function show(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);

        return response()->json($order->load(['items', 'payments', 'refunds', 'kitchenTickets.items']));
    }

    public function hold(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);
        if (in_array($order->status, ['paid', 'completed', 'refunded'], true)) {
            throw ValidationException::withMessages([
                'order' => 'Pesanan yang sudah dibayar tidak dapat ditahan.',
            ]);
        }
        $order->update(['status' => 'held']);

        return response()->json(['message' => 'Order held.', 'data' => $order]);
    }

    public function resume(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);
        $order->update([
            'status' => $order->submitted_at ? 'open' : 'draft',
        ]);

        return response()->json(['message' => 'Order resumed.', 'data' => $order]);
    }

    public function complete(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);
        if (in_array($order->status, ['open', 'held', 'draft'], true)) {
            throw ValidationException::withMessages([
                'order' => 'Open bill harus dibayar sebelum diselesaikan.',
            ]);
        }
        $order->update(['status' => 'completed', 'completed_at' => now()]);

        return response()->json(['message' => 'Order completed.', 'data' => $order]);
    }

    public function void(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);
        $validated = $request->validate([
            'reason' => 'required|string|min:3|max:1000',
            'inventory_outcome' => 'required|string|in:no_stock_return,restore_stock',
        ]);

        $result = $this->orderCancellationService->cancel(
            order: $order,
            user: $request->user(),
            reason: trim($validated['reason']),
            inventoryOutcome: $validated['inventory_outcome'],
        );

        return response()->json([
            'message' => $result['refund']
                ? 'Pesanan dibatalkan dan sisa pembayaran direfund.'
                : 'Pesanan berhasil dibatalkan.',
            'data' => $result['order'],
            'void_transaction' => $result['void'],
            'refund' => $result['refund'],
        ], 201);
    }

    public function refund(Request $request, Order $order)
    {
        $this->ensureOrderIsAccessible($request, $order);

        $validated = $request->validate([
            'payment_id' => 'nullable|uuid|exists:payments,id',
            'order_item_id' => 'nullable|uuid|exists:order_items,id',
            'quantity' => 'nullable|integer|min:1',
            'amount' => 'required|numeric|min:0.01',
            'type' => 'nullable|string|in:full,partial',
            'inventory_outcome' => 'nullable|string|in:no_stock_return,wrong_discard,wrong_remake',
            'reason' => 'required|string',
        ]);

        $orderItem = isset($validated['order_item_id'])
            ? OrderItem::where('order_id', $order->id)->find($validated['order_item_id'])
            : null;
        if (isset($validated['order_item_id']) && ! $orderItem) {
            throw ValidationException::withMessages([
                'order_item_id' => 'Produk refund tidak ditemukan pada pesanan ini.',
            ]);
        }
        if (isset($validated['payment_id']) && ! $order->payments()->whereKey($validated['payment_id'])->exists()) {
            throw ValidationException::withMessages([
                'payment_id' => 'Pembayaran tidak ditemukan pada pesanan ini.',
            ]);
        }

        $outcome = $validated['inventory_outcome'] ?? 'no_stock_return';
        if ($outcome !== 'no_stock_return' && ! $orderItem) {
            throw ValidationException::withMessages([
                'order_item_id' => 'Pilih produk untuk mencatat salah produksi.',
            ]);
        }
        $quantity = $validated['quantity'] ?? ($orderItem ? 1 : null);
        if ($orderItem && $quantity > (int) $orderItem->qty) {
            throw ValidationException::withMessages([
                'quantity' => 'Jumlah refund melebihi jumlah produk pada pesanan.',
            ]);
        }

        $alreadyRefunded = (float) Refund::where('order_id', $order->id)
            ->where('status', 'approved')
            ->sum('amount');
        $remaining = max((float) $order->total - $alreadyRefunded, 0);
        if ((float) $validated['amount'] > $remaining) {
            throw ValidationException::withMessages([
                'amount' => 'Nominal refund melebihi sisa pembayaran yang dapat dikembalikan.',
            ]);
        }

        [$refund, $incident] = DB::transaction(function () use (
            $request,
            $validated,
            $order,
            $orderItem,
            $quantity,
            $outcome,
            $alreadyRefunded,
        ) {
            $refund = Refund::create([
                'order_id' => $order->id,
                'order_item_id' => $orderItem?->id,
                'payment_id' => $validated['payment_id'] ?? null,
                'user_id' => $request->user()?->id,
                'quantity' => $quantity,
                'amount' => $validated['amount'],
                'type' => $validated['type'] ?? 'full',
                'inventory_outcome' => $outcome,
                'reason' => $validated['reason'],
                'status' => 'approved',
            ]);

            $incident = null;
            if ($orderItem && $outcome !== 'no_stock_return') {
                $ticket = $outcome === 'wrong_remake'
                    ? KitchenTicket::where('order_id', $order->id)
                        ->whereHas('items', fn ($items) => $items->where('order_item_id', $orderItem->id))
                        ->latest()
                        ->first()
                    : null;
                $incident = $this->productionIncidentService->record(
                    orderItem: $orderItem,
                    quantity: $quantity ?? 1,
                    resolution: $outcome === 'wrong_remake' ? 'remake' : 'discard',
                    reason: $validated['reason'],
                    user: $request->user(),
                    ticket: $ticket,
                );
            }

            $totalRefunded = $alreadyRefunded + (float) $validated['amount'];
            $order->update([
                'status' => $totalRefunded >= (float) $order->total
                    ? 'refunded'
                    : 'partially_refunded',
            ]);

            return [$refund, $incident];
        });

        return response()->json([
            'message' => 'Refund recorded.',
            'data' => $refund,
            'production_incident' => $incident,
        ], 201);
    }

    private function ensureOrderIsAccessible(Request $request, Order $order): void
    {
        $order->loadMissing('outlet');
        $companyId = $request->user()?->company_id;
        abort_if(
            $companyId && (int) $order->outlet?->company_id !== (int) $companyId,
            404,
        );
    }

    private function ensureOutletIsAccessible(Request $request, Outlet $outlet): void
    {
        $companyId = $request->user()?->company_id;
        abort_if(
            $companyId && (int) $outlet->company_id !== (int) $companyId,
            404,
        );
    }
}
