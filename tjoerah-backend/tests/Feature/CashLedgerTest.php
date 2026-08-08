<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CashLedgerTest extends TestCase
{
    use RefreshDatabase;

    public function test_cash_session_tracks_sales_manual_movements_and_reconciliation(): void
    {
        [$user, $outlet, $product] = $this->context();
        $this->actingAs($user, 'api');

        $opened = $this->postJson('/api/cash/sessions/open', [
            'outlet_id' => $outlet->id,
            'opening_cash' => 100000,
        ])->assertCreated();
        $shiftId = $opened->json('data.id');

        $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'order_type' => 'take_away',
            'receipt_number' => 'CASH-001',
            'subtotal' => 35000,
            'total' => 35000,
            'payment_method' => 'cash',
            'items' => [[
                'product_id' => $product->id,
                'snapshot_name' => 'Latte',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
                'station' => 'bar',
            ]],
            'meta' => ['cash_shift_id' => $shiftId],
        ])->assertCreated();

        $this->postJson('/api/cash/movements', [
            'outlet_id' => $outlet->id,
            'type' => 'cash_out',
            'category' => 'urgent_purchase',
            'amount' => 20000,
            'note' => 'Membeli satu galon air',
            'client_reference' => 'movement-001',
        ])->assertCreated();

        $this->getJson("/api/cash/overview?outlet_id={$outlet->id}")
            ->assertOk()
            ->assertJsonPath('current_shift.summary.opening_cash', 100000)
            ->assertJsonPath('current_shift.summary.cash_sales', 35000)
            ->assertJsonPath('current_shift.summary.manual_cash_out', 20000)
            ->assertJsonPath('current_shift.summary.cash_fund_balance', 80000)
            ->assertJsonPath('current_shift.summary.cash_on_hand', 115000)
            ->assertJsonPath('current_shift.summary.expected_cash', 115000);

        $this->postJson("/api/cash/sessions/{$shiftId}/close", [
            'closing_cash' => 114000,
        ])->assertUnprocessable()->assertJsonValidationErrors('note');

        $this->postJson("/api/cash/sessions/{$shiftId}/close", [
            'closing_cash' => 114000,
            'note' => 'Selisih kas sedang diperiksa oleh kasir.',
        ])->assertOk()
            ->assertJsonPath('data.summary.cash_fund_balance', 80000)
            ->assertJsonPath('data.summary.cash_on_hand', 115000)
            ->assertJsonPath('data.summary.expected_cash', 115000)
            ->assertJsonPath('data.summary.difference', -1000);
    }

    public function test_cash_sale_is_idempotent_when_order_is_retried(): void
    {
        [$user, $outlet, $product] = $this->context();
        $this->actingAs($user, 'api');
        $payload = [
            'outlet_id' => $outlet->id,
            'receipt_number' => 'CASH-RETRY',
            'subtotal' => 35000,
            'total' => 35000,
            'payment_method' => 'cash',
            'items' => [[
                'product_id' => $product->id,
                'snapshot_name' => 'Latte',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
            ]],
            'meta' => ['client_order_id' => 'cash-client-retry'],
        ];

        $this->postJson('/api/orders', $payload)->assertCreated();
        $this->postJson('/api/orders', $payload)->assertOk();

        $this->assertDatabaseCount('cash_movements', 2);
        $this->assertDatabaseHas('cash_movements', [
            'type' => 'sale',
            'amount' => 35000,
        ]);
    }

    public function test_cashiers_share_one_open_cash_session_per_outlet(): void
    {
        [$openingCashier, $outlet] = $this->context();
        $joiningCashier = User::factory()->create([
            'company_id' => $openingCashier->company_id,
            'role' => 'cashier',
        ]);

        $this->actingAs($openingCashier, 'api');
        $opened = $this->postJson('/api/cash/sessions/open', [
            'outlet_id' => $outlet->id,
            'opening_cash' => 100000,
        ])->assertCreated();
        $shiftId = $opened->json('data.id');

        $this->actingAs($joiningCashier, 'api');
        $this->getJson("/api/cash/overview?outlet_id={$outlet->id}")
            ->assertOk()
            ->assertJsonPath('current_shift.id', $shiftId)
            ->assertJsonPath('permissions.can_open', false)
            ->assertJsonPath('permissions.can_record_movement', true)
            ->assertJsonPath('permissions.can_close', false)
            ->assertJsonPath('permissions.joined_shared_shift', true);

        $this->postJson('/api/cash/sessions/open', [
            'outlet_id' => $outlet->id,
            'opening_cash' => 999999,
        ])->assertOk()
            ->assertJsonPath('data.id', $shiftId)
            ->assertJsonPath('data.summary.opening_cash', 100000);

        $this->postJson('/api/cash/movements', [
            'outlet_id' => $outlet->id,
            'type' => 'cash_in',
            'category' => 'change_fund',
            'amount' => 10000,
            'note' => 'Tambahan uang kembalian',
        ])->assertCreated()->assertJsonPath('shift.id', $shiftId);

        $this->postJson("/api/cash/sessions/{$shiftId}/close", [
            'closing_cash' => 110000,
        ])->assertForbidden();

        $this->assertDatabaseCount('shifts', 1);
        $this->assertDatabaseHas('cash_movements', [
            'shift_id' => $shiftId,
            'user_id' => $joiningCashier->id,
            'type' => 'cash_in',
            'amount' => 10000,
        ]);

        $this->actingAs($openingCashier, 'api');
        $this->postJson("/api/cash/sessions/{$shiftId}/close", [
            'closing_cash' => 110000,
        ])->assertOk();
    }

    public function test_manager_only_monitors_and_can_emergency_close_with_a_reason(): void
    {
        [$cashier, $outlet] = $this->context();
        $manager = User::factory()->create([
            'company_id' => $cashier->company_id,
            'role' => 'owner',
        ]);

        $this->actingAs($cashier, 'api');
        $shiftId = $this->postJson('/api/cash/sessions/open', [
            'outlet_id' => $outlet->id,
            'opening_cash' => 50000,
        ])->assertCreated()->json('data.id');

        $this->actingAs($manager, 'api');
        $this->getJson("/api/cash/overview?outlet_id={$outlet->id}")
            ->assertOk()
            ->assertJsonPath('current_shift.id', $shiftId)
            ->assertJsonPath('permissions.monitor_only', true)
            ->assertJsonPath('permissions.can_open', false)
            ->assertJsonPath('permissions.can_record_movement', false)
            ->assertJsonPath('permissions.can_close', false)
            ->assertJsonPath('permissions.can_emergency_close', true);

        $this->postJson('/api/cash/sessions/open', [
            'outlet_id' => $outlet->id,
            'opening_cash' => 10000,
        ])->assertForbidden();
        $this->postJson('/api/cash/movements', [
            'outlet_id' => $outlet->id,
            'type' => 'cash_out',
            'category' => 'other_out',
            'amount' => 5000,
            'note' => 'Tidak boleh dilakukan manager',
        ])->assertForbidden();
        $this->postJson("/api/cash/sessions/{$shiftId}/close", [
            'closing_cash' => 50000,
        ])->assertForbidden();

        $this->postJson("/api/cash/sessions/{$shiftId}/emergency-close", [
            'closing_cash' => 50000,
        ])->assertUnprocessable()->assertJsonValidationErrors('reason');

        $this->postJson("/api/cash/sessions/{$shiftId}/emergency-close", [
            'closing_cash' => 50000,
            'reason' => 'Kasir pembuka tidak dapat melanjutkan shift.',
        ])->assertOk()
            ->assertJsonPath('data.status', 'closed')
            ->assertJsonPath('data.closed_by.id', $manager->id);

        $this->assertDatabaseHas('cash_movements', [
            'shift_id' => $shiftId,
            'user_id' => $manager->id,
            'type' => 'closing_note',
            'category' => 'emergency_cash_close',
        ]);
    }

    public function test_open_bill_requires_a_clear_identity(): void
    {
        [$user, $outlet, $product] = $this->context();
        $this->actingAs($user, 'api');

        $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'receipt_number' => 'OPEN-NO-LABEL',
            'subtotal' => 35000,
            'total' => 35000,
            'is_open_bill' => true,
            'items' => [[
                'product_id' => $product->id,
                'snapshot_name' => 'Latte',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
            ]],
            'meta' => ['client_order_id' => 'open-no-label'],
        ])->assertUnprocessable()->assertJsonValidationErrors('meta.open_bill_label');
    }

    public function test_shift_report_expands_every_payment_method(): void
    {
        [$user, $outlet, $product] = $this->context();
        $this->actingAs($user, 'api');

        $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'receipt_number' => 'SHIFT-SPLIT',
            'subtotal' => 35000,
            'total' => 35000,
            'payment_method' => 'split',
            'items' => [[
                'product_id' => $product->id,
                'snapshot_name' => 'Latte',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
            ]],
            'meta' => [
                'payment_breakdown' => ['cash' => 20000, 'qris' => 15000],
            ],
        ])->assertCreated();

        $this->postJson('/api/orders', [
            'outlet_id' => $outlet->id,
            'receipt_number' => 'SHIFT-DEBIT',
            'subtotal' => 35000,
            'total' => 35000,
            'payment_method' => 'debit_card',
            'items' => [[
                'product_id' => $product->id,
                'snapshot_name' => 'Latte',
                'snapshot_price' => 35000,
                'qty' => 1,
                'total' => 35000,
            ]],
        ])->assertCreated();

        $date = now($outlet->timezone)->toDateString();
        $this->getJson("/api/reports/shift?outlet_id={$outlet->id}&date={$date}")
            ->assertOk()
            ->assertJsonPath('total_orders', 2)
            ->assertJsonPath('gross_revenue', 70000)
            ->assertJsonPath('payment_breakdown.cash', 20000)
            ->assertJsonPath('payment_breakdown.qris', 15000)
            ->assertJsonPath('payment_breakdown.debit', 35000)
            ->assertJsonPath('payment_counts.cash', 1)
            ->assertJsonPath('payment_counts.qris', 1)
            ->assertJsonPath('payment_counts.debit', 1);
    }

    private function context(): array
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $brand = Brand::create([
            'company_id' => $company->id,
            'name' => 'Tjoerah Coffee',
            'code' => 'TCR',
        ]);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'name' => 'Main Outlet',
            'code' => 'MAIN',
            'tax_enabled' => false,
        ]);
        $category = Category::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'name' => 'Coffee',
        ]);
        $product = Product::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'category_id' => $category->id,
            'name' => 'Latte',
            'sku' => 'LAT-CASH',
            'base_price' => 35000,
            'station' => 'bar',
        ]);
        $user = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'cashier',
        ]);

        return [$user, $outlet, $product];
    }
}
