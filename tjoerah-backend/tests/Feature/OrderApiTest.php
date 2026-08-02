<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\CRM\Models\Customer;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\Product;
use App\Domains\Sales\Events\OrderCreated;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

class OrderApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_order_creation_creates_payment_and_kds_ticket(): void
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $brand = Brand::create(['company_id' => $company->id, 'name' => 'Tjoerah Coffee', 'code' => 'TCR']);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'name' => 'Main Outlet',
            'code' => 'MAIN',
            'tax_enabled' => false,
        ]);
        $category = Category::create(['company_id' => $company->id, 'brand_id' => $brand->id, 'name' => 'Coffee']);
        $product = Product::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'category_id' => $category->id,
            'name' => 'Latte',
            'sku' => 'LAT-001',
            'base_price' => 35000,
            'station' => 'bar',
        ]);
        $user = User::factory()->create(['company_id' => $company->id, 'role' => 'cashier']);

        $this->actingAs($user, 'api');

        $response = $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'order_type' => 'take_away',
            'receipt_number' => 'RCP-001',
            'subtotal' => 35000,
            'tax' => 0,
            'total' => 35000,
            'payment_method' => 'cash',
            'items' => [
                [
                    'product_id' => $product->id,
                    'snapshot_name' => 'Latte',
                    'snapshot_price' => 35000,
                    'qty' => 1,
                    'total' => 35000,
                    'station' => 'bar',
                ],
            ],
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.receipt_number', 'RCP-001')
            ->assertJsonPath('data.payments.0.method', 'cash')
            ->assertJsonPath('data.kitchen_tickets.0.station', 'bar');

        $this->assertDatabaseHas('orders', ['receipt_number' => 'RCP-001', 'status' => 'paid']);
        $this->assertDatabaseHas('payments', ['method' => 'cash', 'amount' => 35000]);
        $this->assertDatabaseHas('kitchen_tickets', ['station' => 'bar', 'status' => 'pending']);
        $this->assertDatabaseHas('kitchen_ticket_items', ['name' => 'Latte', 'qty' => 1]);
        $this->assertDatabaseHas('orders', [
            'receipt_number' => 'RCP-001',
            'cogs_total' => 0,
            'gross_profit' => 35000,
        ]);

        Order::where('receipt_number', 'RCP-001')->update(['gross_profit' => 0]);
        $this->getJson('/api/reports/sales')
            ->assertOk()
            ->assertJsonPath('0.gross_profit', 35000);
    }

    public function test_realtime_failure_does_not_reject_or_roll_back_order(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        Event::listen(
            OrderCreated::class,
            fn () => throw new \RuntimeException('Realtime unavailable'),
        );

        $this->actingAs($user, 'api');

        $response = $this->postJson('/api/orders', $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-REALTIME',
            'client-realtime',
        ));

        $response->assertCreated();
        $this->assertDatabaseHas('orders', ['receipt_number' => 'RCP-REALTIME']);
        $this->assertDatabaseHas('kitchen_tickets', ['status' => 'pending']);
    }

    public function test_retrying_same_client_order_is_idempotent(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $this->actingAs($user, 'api');
        $payload = $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-IDEMPOTENT',
            'client-idempotent',
        );

        $this->postJson('/api/orders', $payload)->assertCreated();
        $this->postJson('/api/orders', $payload)
            ->assertOk()
            ->assertJsonPath('message', 'Order already received');

        $this->assertDatabaseCount('orders', 1);
        $this->assertDatabaseCount('payments', 1);
        $this->assertDatabaseCount('kitchen_tickets', 1);
    }

    public function test_same_receipt_from_different_client_is_not_treated_as_retry(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $this->actingAs($user, 'api');

        $this->postJson('/api/orders', $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-COLLISION',
            'client-first',
        ))->assertCreated();

        $this->postJson('/api/orders', $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-COLLISION',
            'client-second',
        ))->assertUnprocessable()
            ->assertJsonValidationErrors('receipt_number');

        $this->assertDatabaseCount('orders', 1);
    }

    public function test_split_payment_is_stored_by_actual_payment_method(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $this->actingAs($user, 'api');
        $payload = $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-SPLIT',
            'client-split',
        );
        $payload['payment_method'] = 'split';
        $payload['meta']['payment_breakdown'] = [
            'cash' => 15000,
            'qris' => 20000,
        ];

        $this->postJson('/api/orders', $payload)
            ->assertCreated()
            ->assertJsonCount(2, 'data.payments')
            ->assertJsonPath('data.payments.0.method', 'cash')
            ->assertJsonPath('data.payments.1.method', 'qris');

        $this->assertDatabaseHas('payments', ['method' => 'cash', 'amount' => 15000]);
        $this->assertDatabaseHas('payments', ['method' => 'qris', 'amount' => 20000]);
    }

    public function test_order_history_can_filter_a_period_and_keep_old_open_bills(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $this->actingAs($user, 'api');

        $this->postJson('/api/orders', $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-TODAY',
            'client-today',
        ))->assertCreated();

        $oldPaid = $this->postJson('/api/orders', $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-OLD-PAID',
            'client-old-paid',
        ))->assertCreated();

        $openPayload = $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-OLD-OPEN',
            'client-old-open',
        );
        unset($openPayload['payment_method']);
        $openPayload['is_open_bill'] = true;
        $oldOpen = $this->postJson('/api/orders', $openPayload)->assertCreated();

        Order::whereKey($oldPaid->json('data.id'))->update([
            'created_at' => now()->subDays(3),
        ]);
        Order::whereKey($oldOpen->json('data.id'))->update([
            'created_at' => now()->subDays(3),
        ]);

        $query = http_build_query([
            'created_from' => now()->startOfDay()->toIso8601String(),
            'created_to' => now()->addDay()->startOfDay()->toIso8601String(),
            'include_open' => 1,
        ]);
        $response = $this->getJson("/api/orders?{$query}")->assertOk();
        $receipts = collect($response->json('data'))->pluck('receipt_number');

        $this->assertCount(2, $receipts);
        $this->assertTrue($receipts->contains('RCP-TODAY'));
        $this->assertTrue($receipts->contains('RCP-OLD-OPEN'));
        $this->assertFalse($receipts->contains('RCP-OLD-PAID'));
    }

    public function test_customer_statistics_and_history_are_updated_once(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $customer = Customer::create([
            'company_id' => $user->company_id,
            'name' => 'Ayu',
        ]);
        $this->actingAs($user, 'api');
        $payload = $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-CUSTOMER',
            'client-customer',
        );
        $payload['customer_id'] = $customer->id;

        $this->postJson('/api/orders', $payload)->assertCreated();
        $this->postJson('/api/orders', $payload)->assertOk();

        $customer->refresh();
        $this->assertSame(1, $customer->visit_count);
        $this->assertSame(35000.0, (float) $customer->total_spent);
        $this->assertNotNull($customer->last_purchase_at);

        $this->getJson("/api/customers/{$customer->id}/orders")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.receipt_number', 'RCP-CUSTOMER')
            ->assertJsonPath('data.0.items.0.snapshot_name', 'Latte');
    }

    public function test_open_bill_is_submitted_once_and_paid_later(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $customer = Customer::create([
            'company_id' => $user->company_id,
            'name' => 'Dina',
        ]);
        $this->actingAs($user, 'api');
        $payload = $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-OPEN-001',
            'client-open-001',
        );
        unset($payload['payment_method']);
        $payload['is_open_bill'] = true;
        $payload['customer_id'] = $customer->id;

        $created = $this->postJson('/api/orders', $payload);
        $created->assertCreated()
            ->assertJsonPath('data.status', 'open')
            ->assertJsonCount(0, 'data.payments')
            ->assertJsonCount(1, 'data.kitchen_tickets');

        $orderId = $created->json('data.id');
        $this->assertDatabaseHas('orders', [
            'id' => $orderId,
            'status' => 'open',
        ]);
        $this->assertDatabaseMissing('payments', ['order_id' => $orderId]);
        $this->assertNotNull(Order::find($orderId)->inventory_deducted_at);
        $this->assertSame(0, $customer->fresh()->visit_count);

        $appendPayload = [
            'client_append_id' => 'append-open-001',
            'items' => [[
                'product_id' => $product->id,
                'snapshot_name' => 'Latte tambahan',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
                'station' => 'bar',
            ]],
        ];
        $this->postJson("/api/orders/{$orderId}/items", $appendPayload)
            ->assertCreated()
            ->assertJsonPath('submission_batch', 2)
            ->assertJsonPath('data.total', 70000)
            ->assertJsonCount(2, 'data.items');
        $this->postJson("/api/orders/{$orderId}/items", $appendPayload)
            ->assertOk()
            ->assertJsonPath('submission_batch', 2)
            ->assertJsonCount(2, 'data.items');
        $this->assertDatabaseCount('kitchen_tickets', 2);
        $this->assertDatabaseHas('order_items', [
            'order_id' => $orderId,
            'snapshot_name' => 'Latte tambahan',
            'submission_batch' => 2,
        ]);
        $this->assertSame(
            2,
            Order::find($orderId)->items()->whereNotNull('inventory_deducted_at')->count(),
        );

        $this->postJson("/api/orders/{$orderId}/pay", [
            'method' => 'cash',
            'payment_breakdown' => ['cash' => 70000],
            'amount_received' => 100000,
            'change' => 30000,
        ])->assertCreated()
            ->assertJsonPath('data.status', 'paid')
            ->assertJsonCount(1, 'data.payments');

        $this->assertDatabaseHas('payments', [
            'order_id' => $orderId,
            'method' => 'cash',
            'amount' => 70000,
        ]);
        $this->assertSame(1, $customer->fresh()->visit_count);

        $this->postJson("/api/orders/{$orderId}/pay", [
            'method' => 'cash',
            'payment_breakdown' => ['cash' => 70000],
        ])->assertOk()
            ->assertJsonPath('message', 'Open bill ini sudah dibayar.');
        $this->assertDatabaseCount('payments', 1);
        $this->assertSame(1, $customer->fresh()->visit_count);
        $this->assertSame(70000.0, (float) $customer->fresh()->total_spent);
    }

    public function test_automatic_kds_mode_completes_tickets_without_confirmation(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $user->update(['role' => 'owner']);
        $this->actingAs($user, 'api');

        $this->putJson('/api/transaction-settings', [
            'outlet_id' => $outlet->id,
            'tax_enabled' => false,
            'tax_rate' => 0,
            'kds_mode' => 'automatic',
        ])->assertOk()
            ->assertJsonPath('data.kds_mode', 'automatic');

        $this->postJson('/api/orders', $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-AUTO-KDS',
            'client-auto-kds',
        ))->assertCreated()
            ->assertJsonPath('data.kitchen_tickets.0.status', 'completed')
            ->assertJsonPath('data.kitchen_tickets.0.items.0.status', 'completed');

        $this->assertDatabaseHas('kitchen_tickets', [
            'outlet_id' => $outlet->id,
            'status' => 'completed',
        ]);
    }

    public function test_manual_item_is_charged_without_inventory_or_production_ticket(): void
    {
        [$user, $outlet] = $this->createOrderContext();
        $this->actingAs($user, 'api');

        $response = $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'order_type' => 'take_away',
            'receipt_number' => 'RCP-MANUAL-001',
            'subtotal' => 30000,
            'tax' => 0,
            'total' => 30000,
            'payment_method' => 'cash',
            'items' => [[
                'is_manual' => true,
                'snapshot_name' => 'Biaya dekorasi ulang tahun',
                'snapshot_price' => 15000,
                'qty' => 2,
                'total' => 1,
                'station' => 'kitchen',
            ]],
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.total', 30000)
            ->assertJsonPath('data.items.0.product_id', null)
            ->assertJsonPath('data.items.0.station', 'cashier')
            ->assertJsonPath('data.items.0.total', 30000)
            ->assertJsonCount(0, 'data.kitchen_tickets');

        $this->assertDatabaseHas('order_items', [
            'snapshot_name' => 'Biaya dekorasi ulang tahun',
            'product_id' => null,
            'station' => 'cashier',
            'total' => 30000,
            'cogs_total' => 0,
        ]);
        $this->assertDatabaseCount('kitchen_tickets', 0);
        $this->assertNotNull(
            Order::where('receipt_number', 'RCP-MANUAL-001')
                ->firstOrFail()
                ->items()
                ->firstOrFail()
                ->inventory_deducted_at,
        );
    }

    public function test_catalog_item_still_requires_a_product(): void
    {
        [$user, $outlet] = $this->createOrderContext();
        $this->actingAs($user, 'api');

        $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'receipt_number' => 'RCP-NO-PRODUCT',
            'payment_method' => 'cash',
            'subtotal' => 10000,
            'total' => 10000,
            'items' => [[
                'snapshot_name' => 'Item tanpa produk',
                'snapshot_price' => 10000,
                'qty' => 1,
                'total' => 10000,
            ]],
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('items.0.product_id');
    }

    public function test_outlet_tax_setting_is_used_as_server_source_of_truth(): void
    {
        [$user, $outlet, $product] = $this->createOrderContext();
        $user->update(['role' => 'owner']);
        $this->actingAs($user, 'api');

        $this->putJson('/api/transaction-settings', [
            'outlet_id' => $outlet->id,
            'tax_enabled' => true,
            'tax_rate' => 8.5,
        ])->assertOk()
            ->assertJsonPath('data.tax_enabled', true)
            ->assertJsonPath('data.tax_rate', 8.5);

        $payload = $this->orderPayload(
            $outlet->id,
            $product->id,
            'RCP-TAX-001',
            'client-tax-001',
        );
        $payload['tax'] = 0;
        $payload['total'] = 35000;

        $this->postJson('/api/orders', $payload)
            ->assertCreated()
            ->assertJsonPath('data.tax_rate', 8.5)
            ->assertJsonPath('data.tax', 2975)
            ->assertJsonPath('data.total', 37975);
    }

    private function createOrderContext(): array
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $brand = Brand::create(['company_id' => $company->id, 'name' => 'Tjoerah Coffee', 'code' => 'TCR']);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'name' => 'Main Outlet',
            'code' => 'MAIN',
            'tax_enabled' => false,
        ]);
        $category = Category::create(['company_id' => $company->id, 'brand_id' => $brand->id, 'name' => 'Coffee']);
        $product = Product::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'category_id' => $category->id,
            'name' => 'Latte',
            'sku' => 'LAT-001',
            'base_price' => 35000,
            'station' => 'bar',
        ]);
        $user = User::factory()->create(['company_id' => $company->id, 'role' => 'cashier']);

        return [$user, $outlet, $product];
    }

    private function orderPayload(
        int $outletId,
        int $productId,
        string $receiptNumber,
        string $clientOrderId,
    ): array {
        return [
            'outlet_id' => $outletId,
            'order_type' => 'take_away',
            'receipt_number' => $receiptNumber,
            'subtotal' => 35000,
            'tax' => 0,
            'total' => 35000,
            'payment_method' => 'cash',
            'items' => [[
                'product_id' => $productId,
                'snapshot_name' => 'Latte',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
                'station' => 'bar',
            ]],
            'meta' => ['client_order_id' => $clientOrderId],
        ];
    }
}
