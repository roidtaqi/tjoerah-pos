<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\CRM\Models\Customer;
use App\Domains\CRM\Models\LoyaltyPoint;
use App\Domains\Sales\Services\OrderService;
use App\Domains\Sales\DTOs\OrderData;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CrmLoyaltyTest extends TestCase
{
    use RefreshDatabase;

    public function test_loyalty_earning_and_redemption_flow(): void
    {
        // 1. Setup Base Organization
        $company = Company::create(['name' => 'Tjoerah Corp']);
        $brand = Brand::create(['company_id' => $company->id, 'name' => 'Tjoerah Coffee', 'code' => 'TCR']);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'name' => 'Kuningan Outlet',
            'code' => 'KNG',
        ]);
        $user = User::factory()->create(['company_id' => $company->id]);

        // 2. Setup Customer
        $customer = Customer::create([
            'company_id' => $company->id,
            'name' => 'John Doe',
            'email' => 'john@example.com',
            'phone' => '08123456789',
        ]);

        // 3. Place Order (Total: Rp 55.000)
        // Expected Points: floor(55000 / 10000) = 5 points
        $orderService = app(OrderService::class);
        $orderData = new OrderData(
            outletId: $outlet->id,
            userId: $user->id,
            items: [],
            subtotal: 55000,
            tax: 0,
            total: 55000,
            paymentMethod: 'cash',
            receiptNumber: 'REC-0101',
            customerId: $customer->id,
        );

        $order = $orderService->placeOrder($orderData);

        // 4. Verify Earning
        $balance = \App\Domains\CRM\Services\LoyaltyService::getCustomerPointsBalance($customer->id);
        $this->assertEquals(5, $balance);

        // 5. Test Redemption - Insufficient Balance (Requesting 10 points)
        $response = $this->actingAs($user)->postJson('/api/loyalty/redeem', [
            'customer_id' => $customer->id,
            'points' => 10,
        ]);
        $response->assertStatus(422);

        // 6. Test Redemption - Successful (Redeeming 3 points)
        $response2 = $this->actingAs($user)->postJson('/api/loyalty/redeem', [
            'customer_id' => $customer->id,
            'points' => 3,
        ]);
        $response2->assertStatus(201);

        // 7. Verify new balance
        // 5 - 3 = 2 points remaining.
        $newBalance = \App\Domains\CRM\Services\LoyaltyService::getCustomerPointsBalance($customer->id);
        $this->assertEquals(2, $newBalance);
    }
}
