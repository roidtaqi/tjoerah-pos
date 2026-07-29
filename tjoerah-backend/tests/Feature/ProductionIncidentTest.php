<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\StockMovement;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Services\InventoryService;
use App\Domains\POS\Models\Product;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeItem;
use App\Domains\Recipe\Models\RecipeVersion;
use App\Domains\Recipe\Services\RecipeService;
use App\Domains\Sales\DTOs\OrderData;
use App\Domains\Sales\Services\OrderService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ProductionIncidentTest extends TestCase
{
    use RefreshDatabase;

    public function test_wrong_product_and_remake_track_waste_without_double_deducting_original_stock(): void
    {
        $context = $this->placeRecipeOrder();
        $order = $context['order'];
        $orderItem = $order->items->first();
        $ticket = $order->kitchenTickets->first();

        $this->assertSame(95.0, $this->stockFor($context['ingredient']));
        $this->assertSame(500.0, (float) $orderItem->cogs_total);

        $this->actingAs($context['user'], 'api')
            ->postJson('/api/inventory/production-incidents', [
                'order_item_id' => $orderItem->id,
                'ticket_id' => $ticket->id,
                'quantity' => 1,
                'resolution' => 'discard',
                'reason' => 'Susu pecah saat steaming.',
            ])
            ->assertCreated()
            ->assertJsonPath('data.waste_type', 'wrong_production')
            ->assertJsonPath('data.resolution', 'discard')
            ->assertJsonPath('data.original_stock_consumed', true);

        $this->assertSame(95.0, $this->stockFor($context['ingredient']));

        $this->postJson('/api/inventory/production-incidents', [
            'order_item_id' => $orderItem->id,
            'ticket_id' => $ticket->id,
            'quantity' => 1,
            'resolution' => 'remake',
            'reason' => 'Pesanan dibuat dengan gula yang salah.',
        ])
            ->assertCreated()
            ->assertJsonPath('data.resolution', 'remake')
            ->assertJsonPath('ticket.status', 'preparing');

        $this->assertSame(90.0, $this->stockFor($context['ingredient']));
        $this->assertSame(1000.0, (float) $orderItem->fresh()->cogs_total);
        $this->assertDatabaseCount('wastages', 2);
    }

    public function test_refund_without_production_incident_keeps_stock_and_reduces_net_sales(): void
    {
        $context = $this->placeRecipeOrder();
        $order = $context['order'];
        $stockBeforeRefund = $this->stockFor($context['ingredient']);

        $this->actingAs($context['user'], 'api')
            ->postJson("/api/orders/{$order->id}/refund", [
                'amount' => 20000,
                'type' => 'full',
                'inventory_outcome' => 'no_stock_return',
                'reason' => 'Pelanggan membatalkan setelah minuman selesai.',
            ])
            ->assertCreated()
            ->assertJsonPath('data.inventory_outcome', 'no_stock_return')
            ->assertJsonPath('production_incident', null);

        $this->assertSame($stockBeforeRefund, $this->stockFor($context['ingredient']));
        $this->assertDatabaseCount('wastages', 0);
        $this->assertSame('refunded', $order->fresh()->status);

        $this->getJson('/api/reports/sales')
            ->assertOk()
            ->assertJsonPath('0.total_sales', 0)
            ->assertJsonPath('0.refunds', 20000);
    }

    public function test_refund_for_wrong_product_can_requeue_ticket_and_consume_remake_stock(): void
    {
        $context = $this->placeRecipeOrder();
        $order = $context['order'];
        $orderItem = $order->items->first();
        $ticket = $order->kitchenTickets->first();
        $ticket->update([
            'status' => 'completed',
            'completed_at' => now(),
        ]);

        $this->actingAs($context['user'], 'api')
            ->postJson("/api/orders/{$order->id}/refund", [
                'order_item_id' => $orderItem->id,
                'quantity' => 1,
                'amount' => 10000,
                'type' => 'partial',
                'inventory_outcome' => 'wrong_remake',
                'reason' => 'Minuman dibuat dengan varian yang salah.',
            ])
            ->assertCreated()
            ->assertJsonPath('data.inventory_outcome', 'wrong_remake')
            ->assertJsonPath('production_incident.resolution', 'remake');

        $this->assertSame('preparing', $ticket->fresh()->status);
        $this->assertSame(90.0, $this->stockFor($context['ingredient']));
        $this->assertSame(1000.0, (float) $orderItem->fresh()->cogs_total);
        $this->assertSame('partially_refunded', $order->fresh()->status);
        $this->assertDatabaseCount('wastages', 1);
    }

    public function test_cashier_cannot_record_a_refund(): void
    {
        $context = $this->placeRecipeOrder();
        $cashier = User::factory()->create([
            'company_id' => $context['user']->company_id,
            'role' => 'cashier',
        ]);

        $this->actingAs($cashier, 'api')
            ->postJson("/api/orders/{$context['order']->id}/refund", [
                'amount' => 20000,
                'inventory_outcome' => 'no_stock_return',
                'reason' => 'Refund tanpa otorisasi.',
            ])
            ->assertForbidden();

        $this->assertDatabaseCount('refunds', 0);
    }

    private function placeRecipeOrder(): array
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
            'name' => 'Renon',
            'code' => 'RNN',
        ]);
        $warehouse = Warehouse::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'name' => 'Gudang Renon',
            'is_active' => true,
        ]);
        $user = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
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
            userId: $user->id,
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
            'name' => 'Batch Kopi Susu',
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

        $order = app(OrderService::class)->placeOrder(new OrderData(
            outletId: $outlet->id,
            userId: $user->id,
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
            paymentMethod: 'cash',
            receiptNumber: 'REC-INCIDENT-'.fake()->unique()->numerify('####'),
        ));

        return [
            'user' => $user,
            'ingredient' => $ingredient,
            'order' => $order,
        ];
    }

    private function stockFor(InventoryItem $item): float
    {
        return (float) StockMovement::where('inventory_item_id', $item->id)
            ->sum('quantity');
    }
}
