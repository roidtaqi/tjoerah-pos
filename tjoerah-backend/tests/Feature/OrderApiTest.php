<?php

namespace Tests\Feature;

use App\Models\Brand;
use App\Models\Category;
use App\Models\Company;
use App\Models\Outlet;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
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

        Sanctum::actingAs($user);

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
}
