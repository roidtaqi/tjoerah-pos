<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Models\GoodsReceipt;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeVersion;
use App\Domains\Recipe\Models\RecipeItem;
use App\Domains\POS\Models\Product;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\Order;
use App\Domains\Sales\Services\OrderService;
use App\Domains\Sales\DTOs\OrderData;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class InventoryRecipeTest extends TestCase
{
    use RefreshDatabase;

    public function test_weighted_average_cost_and_auto_deduction_flow(): void
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
        $warehouse = Warehouse::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'name' => 'Kuningan Main Warehouse',
            'is_active' => true,
        ]);
        $user = User::factory()->create(['company_id' => $company->id]);

        // 2. Setup Inventory Item (Raw Material: Coffee Beans)
        $coffeeBeans = InventoryItem::create([
            'company_id' => $company->id,
            'name' => 'Arabica Coffee Beans',
            'sku' => 'BEANS-001',
            'item_type' => 'raw_material',
            'unit' => 'g',
            'weighted_average_cost' => 100, // Rp 100 per gram initial cost
        ]);

        // 3. Receive Goods (Goods Receipt) - recalculated WAC
        // Incoming: 1000g at Rp 120/gram.
        // Formula: (0*100 + 1000*120) / 1000 = 120.
        $receipt = GoodsReceipt::create([
            'warehouse_id' => $warehouse->id,
            'receipt_number' => 'GR-001',
            'received_at' => now(),
            'user_id' => $user->id,
        ]);

        \App\Domains\Inventory\Services\InventoryService::recordMovement(
            itemId: $coffeeBeans->id,
            warehouseId: $warehouse->id,
            quantity: 1000,
            type: 'stock_in',
            unitCost: 120,
            referenceType: GoodsReceipt::class,
            referenceId: $receipt->id,
            referenceNumber: $receipt->receipt_number,
            userId: $user->id
        );

        $coffeeBeans->refresh();
        $this->assertEquals(120, (float) $coffeeBeans->weighted_average_cost);

        // 4. Create Product & Recipe (Espresso Shot)
        $category = Category::create(['company_id' => $company->id, 'brand_id' => $brand->id, 'name' => 'Beverage']);
        $product = Product::create([
            'company_id' => $company->id,
            'brand_id' => $brand->id,
            'category_id' => $category->id,
            'name' => 'Single Espresso',
            'sku' => 'ESP-001',
            'base_price' => 20000,
        ]);

        $recipe = Recipe::create([
            'company_id' => $company->id,
            'product_id' => $product->id,
            'name' => 'Espresso Recipe',
            'status' => 'active',
            'active_version' => 1,
            'yield_quantity' => 1,
            'yield_unit' => 'shot',
        ]);

        $version = RecipeVersion::create([
            'recipe_id' => $recipe->id,
            'version' => 1,
            'status' => 'active',
        ]);

        // Recipe uses 15g Coffee Beans with 0% waste
        $recipeItem = RecipeItem::create([
            'recipe_id' => $recipe->id,
            'recipe_version_id' => $version->id,
            'inventory_item_id' => $coffeeBeans->id,
            'quantity' => 15,
            'unit' => 'g',
            'unit_cost' => 120,
            'total_cost' => 15 * 120,
        ]);

        // Propagate / calculate version cost
        \App\Domains\Recipe\Services\RecipeService::updateRecipeVersionTotalCost($version->id);

        $recipe->refresh();
        $this->assertEquals(15 * 120, (float) $recipe->current_cost);

        // 5. Place an Order via OrderService
        $orderService = app(OrderService::class);
        $orderData = new OrderData(
            outletId: $outlet->id,
            userId: $user->id,
            items: [
                [
                    'product_id' => $product->id,
                    'snapshot_name' => 'Single Espresso',
                    'snapshot_price' => 20000,
                    'qty' => 2, // 2x Single Espresso = uses 30g beans
                    'total' => 40000,
                ]
            ],
            subtotal: 40000,
            tax: 0,
            total: 40000,
            paymentMethod: 'cash',
            receiptNumber: 'REC-0099',
        );

        $order = $orderService->placeOrder($orderData);

        // 6. Verify stock deduction
        // 1000g - (15g * 2) = 970g remaining.
        $totalStock = \App\Domains\Inventory\Models\StockMovement::where('inventory_item_id', $coffeeBeans->id)
            ->where('warehouse_id', $warehouse->id)
            ->sum('quantity');

        $this->assertEquals(970, (float) $totalStock);

        // Verify that the order item COGS was written
        $orderItem = $order->items->first();
        $this->assertEquals(15 * 120 * 2, (float) $orderItem->cogs_total);
    }

    public function test_wastage_exceeding_threshold_triggers_system_alert(): void
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
        $warehouse = Warehouse::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'name' => 'Kuningan Main Warehouse',
            'is_active' => true,
        ]);
        $user = User::factory()->create(['company_id' => $company->id]);

        $coffeeBeans = InventoryItem::create([
            'company_id' => $company->id,
            'name' => 'Arabica Coffee Beans',
            'sku' => 'BEANS-001',
            'item_type' => 'raw_material',
            'unit' => 'g',
            'weighted_average_cost' => 100, // Rp 100 per gram initial cost
        ]);

        // Place Order of Rp 50.000
        $orderService = app(OrderService::class);
        $orderData = new OrderData(
            outletId: $outlet->id,
            userId: $user->id,
            items: [],
            subtotal: 50000,
            tax: 0,
            total: 50000,
            paymentMethod: 'cash',
            receiptNumber: 'REC-0102',
        );
        $orderService->placeOrder($orderData);

        // Log Spoilage of 20g (Value: 20 * Rp 100 = Rp 2.000).
        // Rp 2.000 / Rp 50.000 = 4% (which is > 3% threshold).
        $response = $this->actingAs($user)->postJson('/api/inventory/wastage', [
            'outlet_id' => $outlet->id,
            'warehouse_id' => $warehouse->id,
            'inventory_item_id' => $coffeeBeans->id,
            'quantity' => 20,
            'waste_type' => 'spoilage',
            'reason' => 'Dropped on the floor',
        ]);

        $response->assertStatus(201);

        // Verify SystemAlert was logged
        $alert = \App\Domains\Reporting\Models\SystemAlert::where('outlet_id', $outlet->id)
            ->where('alert_type', 'excessive_waste')
            ->first();

        $this->assertNotNull($alert);
        $this->assertEquals('Excessive Spoilage Alert', $alert->title);
    }
}
