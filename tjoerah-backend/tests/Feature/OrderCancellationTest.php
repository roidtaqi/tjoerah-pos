<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\CRM\Models\Customer;
use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\StockMovement;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Services\InventoryService;
use App\Domains\POS\Models\DiningTable;
use App\Domains\POS\Models\Product;
use App\Domains\POS\Models\TableSession;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeItem;
use App\Domains\Recipe\Models\RecipeVersion;
use App\Domains\Recipe\Services\RecipeService;
use App\Domains\Sales\DTOs\OrderData;
use App\Domains\Sales\Services\OrderService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OrderCancellationTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_cancel_open_bill_restore_stock_and_release_operations(): void
    {
        $context = $this->placeRecipeOrder(isOpenBill: true, withTable: true);

        $this->assertSame(95.0, $this->stockFor($context['ingredient']));

        $this->actingAs($context['admin'], 'api')
            ->postJson("/api/orders/{$context['order']->id}/void", [
                'reason' => 'Pelanggan membatalkan sebelum produksi dimulai.',
                'inventory_outcome' => 'restore_stock',
            ])
            ->assertCreated()
            ->assertJsonPath('data.status', 'voided')
            ->assertJsonPath('void_transaction.previous_status', 'open')
            ->assertJsonPath('void_transaction.inventory_outcome', 'restore_stock')
            ->assertJsonPath('refund', null);

        $this->assertSame(100.0, $this->stockFor($context['ingredient']));
        $this->assertDatabaseHas('stock_movements', [
            'reference_number' => $context['order']->receipt_number,
            'movement_type' => 'void_return',
            'quantity' => 5,
        ]);
        $this->assertDatabaseHas('kitchen_tickets', [
            'order_id' => $context['order']->id,
            'status' => 'cancelled',
        ]);
        $this->assertDatabaseHas('kitchen_ticket_items', ['status' => 'cancelled']);
        $this->assertDatabaseHas('table_sessions', [
            'table_id' => $context['table']->id,
            'status' => 'closed',
        ]);
        $this->assertDatabaseHas('tables', [
            'id' => $context['table']->id,
            'status' => 'cleaning',
        ]);
        $this->assertDatabaseCount('refunds', 0);
    }

    public function test_admin_cancels_paid_order_and_refunds_remaining_payment(): void
    {
        $context = $this->placeRecipeOrder(withCustomer: true);

        $this->actingAs($context['admin'], 'api')
            ->postJson("/api/orders/{$context['order']->id}/void", [
                'reason' => 'Transaksi kasir salah dan harus dibatalkan.',
                'inventory_outcome' => 'no_stock_return',
            ])
            ->assertCreated()
            ->assertJsonPath('data.status', 'voided')
            ->assertJsonPath('refund.amount', '20000.00');

        $this->assertSame(95.0, $this->stockFor($context['ingredient']));
        $this->assertDatabaseHas('refunds', [
            'order_id' => $context['order']->id,
            'amount' => 20000,
            'status' => 'approved',
        ]);
        $this->assertSame(0.0, (float) $context['customer']->fresh()->total_spent);
        $this->assertSame(0, $context['customer']->fresh()->visit_count);

        $this->getJson('/api/reports/sales')
            ->assertOk()
            ->assertJsonPath('0.total_sales', 0)
            ->assertJsonPath('0.refunds', 20000)
            ->assertJsonPath('0.cogs', 500);

        $this->postJson("/api/orders/{$context['order']->id}/void", [
            'reason' => 'Percobaan pembatalan ulang.',
            'inventory_outcome' => 'no_stock_return',
        ])->assertUnprocessable();

        $this->assertDatabaseCount('refunds', 1);
        $this->assertDatabaseCount('void_transactions', 1);
    }

    public function test_cancelling_partially_refunded_order_only_refunds_the_remainder(): void
    {
        $context = $this->placeRecipeOrder();
        $this->actingAs($context['admin'], 'api');

        $this->postJson("/api/orders/{$context['order']->id}/refund", [
            'amount' => 5000,
            'type' => 'partial',
            'inventory_outcome' => 'no_stock_return',
            'reason' => 'Refund sebagian sebelum pembatalan.',
        ])->assertCreated();

        $this->postJson("/api/orders/{$context['order']->id}/void", [
            'reason' => 'Sisa transaksi ikut dibatalkan.',
            'inventory_outcome' => 'no_stock_return',
        ])->assertCreated()
            ->assertJsonPath('refund.amount', '15000.00');

        $this->assertDatabaseCount('refunds', 2);
        $this->assertSame(
            20000.0,
            (float) $context['order']->refunds()->where('status', 'approved')->sum('amount'),
        );
    }

    public function test_cancelling_fully_refunded_order_does_not_create_another_refund(): void
    {
        $context = $this->placeRecipeOrder();
        $this->actingAs($context['admin'], 'api');

        $this->postJson("/api/orders/{$context['order']->id}/refund", [
            'amount' => 20000,
            'type' => 'full',
            'inventory_outcome' => 'no_stock_return',
            'reason' => 'Pembayaran sudah dikembalikan penuh.',
        ])->assertCreated();

        $this->postJson("/api/orders/{$context['order']->id}/void", [
            'reason' => 'Tutup pesanan yang telah direfund.',
            'inventory_outcome' => 'no_stock_return',
        ])->assertCreated()
            ->assertJsonPath('data.status', 'voided')
            ->assertJsonPath('refund', null);

        $this->assertDatabaseCount('refunds', 1);
    }

    public function test_cashier_cannot_cancel_an_order(): void
    {
        $context = $this->placeRecipeOrder();
        $cashier = User::factory()->create([
            'company_id' => $context['admin']->company_id,
            'role' => 'cashier',
        ]);

        $this->actingAs($cashier, 'api')
            ->postJson("/api/orders/{$context['order']->id}/void", [
                'reason' => 'Pembatalan tanpa izin.',
                'inventory_outcome' => 'no_stock_return',
            ])
            ->assertForbidden();

        $this->assertDatabaseCount('void_transactions', 0);
        $this->assertDatabaseCount('refunds', 0);
    }

    /** @return array<string, mixed> */
    private function placeRecipeOrder(
        bool $isOpenBill = false,
        bool $withCustomer = false,
        bool $withTable = false,
    ): array {
        $company = Company::create(['name' => 'Tjoerah']);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'name' => 'Renon',
            'code' => 'RNN',
        ]);
        $warehouse = Warehouse::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'name' => 'Gudang Renon',
            'is_active' => true,
        ]);
        $admin = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'admin',
        ]);
        $ingredient = InventoryItem::create([
            'company_id' => $company->id,
            'name' => 'Biji Kopi',
            'unit' => 'g',
            'weighted_average_cost' => 100,
        ]);
        InventoryService::recordMovement(
            itemId: $ingredient->id,
            warehouseId: $warehouse->id,
            quantity: 100,
            type: 'stock_in',
            unitCost: 100,
            userId: $admin->id,
        );

        $product = Product::create([
            'company_id' => $company->id,
            'name' => 'Kopi Susu',
            'base_price' => 20000,
            'station' => 'bar',
        ]);
        $recipe = Recipe::create([
            'company_id' => $company->id,
            'product_id' => $product->id,
            'name' => 'Kopi Susu',
            'status' => 'active',
            'active_version' => 1,
            'yield_quantity' => 2,
            'yield_unit' => 'porsi',
        ]);
        $version = RecipeVersion::create([
            'recipe_id' => $recipe->id,
            'version' => 1,
            'status' => 'active',
        ]);
        RecipeItem::create([
            'recipe_id' => $recipe->id,
            'recipe_version_id' => $version->id,
            'inventory_item_id' => $ingredient->id,
            'quantity' => 10,
            'unit' => 'g',
            'unit_cost' => 100,
            'total_cost' => 1000,
        ]);
        RecipeService::updateRecipeVersionTotalCost($version->id);

        $customer = $withCustomer
            ? Customer::create([
                'company_id' => $company->id,
                'name' => 'Ayu',
            ])
            : null;
        $table = $withTable
            ? DiningTable::create([
                'outlet_id' => $outlet->id,
                'name' => 'Meja 1',
                'status' => 'occupied',
            ])
            : null;

        $order = app(OrderService::class)->placeOrder(new OrderData(
            outletId: $outlet->id,
            userId: $admin->id,
            items: [[
                'product_id' => $product->id,
                'snapshot_name' => $product->name,
                'snapshot_price' => 20000,
                'qty' => 1,
                'total' => 20000,
                'station' => 'bar',
            ]],
            subtotal: 20000,
            tax: 0,
            total: 20000,
            paymentMethod: $isOpenBill ? 'open_bill' : 'cash',
            receiptNumber: 'REC-CANCEL-'.fake()->unique()->numerify('####'),
            customerId: $customer?->id,
            tableId: $table?->id,
            isOpenBill: $isOpenBill,
        ));

        if ($table) {
            TableSession::create([
                'table_id' => $table->id,
                'status' => 'open',
                'opened_at' => now(),
            ]);
        }

        return compact('admin', 'ingredient', 'order', 'customer', 'table');
    }

    private function stockFor(InventoryItem $item): float
    {
        return (float) StockMovement::where('inventory_item_id', $item->id)
            ->sum('quantity');
    }
}
