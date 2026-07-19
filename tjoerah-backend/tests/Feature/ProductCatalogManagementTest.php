<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Role;
use App\Domains\Core\Models\User;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ProductCatalogManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_read_update_and_delete_products(): void
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $category = Category::create([
            'company_id' => $company->id,
            'name' => 'Kopi',
            'is_active' => true,
        ]);
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $this->actingAs($owner, 'api');

        $product = $this->postJson('/api/products', [
            'name' => 'Kopi Susu Tjoerah',
            'description' => 'Kopi susu gula aren.',
            'category_id' => $category->id,
            'base_price' => 28000,
            'sku' => 'KST-001',
            'barcode' => '899000000001',
            'product_type' => 'simple',
            'station' => 'bar',
            'sla_minutes' => 8,
            'track_inventory' => true,
            'is_active' => true,
        ])->assertCreated()
            ->assertJsonPath('name', 'Kopi Susu Tjoerah')
            ->assertJsonPath('company_id', $company->id)
            ->assertJsonPath('category.name', 'Kopi')
            ->json();

        $this->getJson("/api/products/{$product['id']}")
            ->assertOk()
            ->assertJsonPath('sku', 'KST-001');

        $this->patchJson("/api/products/{$product['id']}", [
            'name' => 'Kopi Susu Aren',
            'base_price' => 30000,
            'sku' => 'KST-001',
            'barcode' => '899000000001',
            'is_active' => false,
        ])->assertOk()
            ->assertJsonPath('name', 'Kopi Susu Aren')
            ->assertJsonPath('base_price', '30000.00')
            ->assertJsonPath('is_active', false);

        $this->getJson('/api/products?status=inactive')
            ->assertOk()
            ->assertJsonPath('data.0.id', $product['id']);

        $this->getJson('/api/catalog/sync')
            ->assertOk()
            ->assertJsonCount(0, 'products');

        $this->deleteJson("/api/products/{$product['id']}")->assertNoContent();
        $this->assertSoftDeleted('products', ['id' => $product['id']]);
    }

    public function test_admin_direct_or_assigned_role_can_manage_products(): void
    {
        $admin = User::factory()->create(['role' => 'admin']);
        $this->actingAs($admin, 'api')
            ->postJson('/api/products', [
                'name' => 'Admin Product',
                'base_price' => 15000,
            ])
            ->assertCreated();

        $assignedAdmin = User::factory()->create(['role' => 'cashier']);
        $role = Role::create([
            'name' => 'Administrator',
            'slug' => 'administrator',
            'scope' => 'company',
        ]);
        $assignedAdmin->roles()->attach($role->id);

        $this->actingAs($assignedAdmin, 'api')
            ->postJson('/api/products', [
                'name' => 'Assigned Admin Product',
                'base_price' => 18000,
            ])
            ->assertCreated();
    }

    public function test_cashier_cannot_mutate_products(): void
    {
        $cashier = User::factory()->create(['role' => 'cashier']);
        $product = Product::create(['name' => 'Americano', 'base_price' => 22000]);
        $this->actingAs($cashier, 'api');

        $this->postJson('/api/products', [
            'name' => 'Forbidden Product',
            'base_price' => 10000,
        ])->assertForbidden();
        $this->patchJson("/api/products/{$product->id}", [
            'base_price' => 25000,
        ])->assertForbidden();
        $this->deleteJson("/api/products/{$product->id}")->assertForbidden();
    }

    public function test_owner_cannot_manage_another_company_product(): void
    {
        $ownerCompany = Company::create(['name' => 'Owner Company']);
        $otherCompany = Company::create(['name' => 'Other Company']);
        $owner = User::factory()->create([
            'company_id' => $ownerCompany->id,
            'role' => 'owner',
        ]);
        $product = Product::create([
            'company_id' => $otherCompany->id,
            'name' => 'Private Product',
            'base_price' => 12000,
        ]);

        $this->actingAs($owner, 'api')
            ->patchJson("/api/products/{$product->id}", ['base_price' => 14000])
            ->assertNotFound();
    }
}
