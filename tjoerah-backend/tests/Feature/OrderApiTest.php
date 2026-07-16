<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\POS\Models\Category;
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

    private function createOrderContext(): array
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $brand = Brand::create(['company_id' => $company->id, 'name' => 'Tjoerah Coffee', 'code' => 'TCR']);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'name' => 'Main Outlet',
            'code' => 'MAIN',
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
