<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\User;
use App\Domains\Inventory\Models\InventoryItem;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class InventoryItemManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_and_update_company_inventory_item(): void
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $otherCompany = Company::create(['name' => 'Other']);
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);

        $item = $this->actingAs($owner, 'api')
            ->postJson('/api/inventory/items', [
                'company_id' => $otherCompany->id,
                'name' => 'Biji Kopi',
                'sku' => 'BEAN-01',
                'item_type' => 'raw_material',
                'unit' => 'g',
                'weighted_average_cost' => 150,
                'minimum_stock' => 1000,
                'is_active' => true,
            ])
            ->assertCreated()
            ->assertJsonPath('company_id', $company->id)
            ->assertJsonPath('name', 'Biji Kopi')
            ->json();

        $this->patchJson("/api/inventory/items/{$item['id']}", [
            'name' => 'Biji Kopi House Blend',
            'minimum_stock' => 1500,
            'is_active' => false,
        ])
            ->assertOk()
            ->assertJsonPath('name', 'Biji Kopi House Blend')
            ->assertJsonPath('minimum_stock', '1500.0000')
            ->assertJsonPath('is_active', false);
    }

    public function test_inventory_items_are_scoped_and_mutations_are_protected(): void
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $otherCompany = Company::create(['name' => 'Other']);
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $cashier = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'cashier',
        ]);
        InventoryItem::create([
            'company_id' => $company->id,
            'name' => 'Visible',
            'unit' => 'pcs',
        ]);
        $otherItem = InventoryItem::create([
            'company_id' => $otherCompany->id,
            'name' => 'Private',
            'unit' => 'pcs',
        ]);

        $this->actingAs($owner, 'api')
            ->getJson('/api/inventory')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Visible');
        $this->patchJson("/api/inventory/items/{$otherItem->id}", [
            'name' => 'Changed',
        ])->assertNotFound();

        $this->actingAs($cashier, 'api')
            ->postJson('/api/inventory/items', [
                'name' => 'Forbidden',
                'unit' => 'pcs',
            ])
            ->assertForbidden();
        $this->patchJson("/api/inventory/items/{$otherItem->id}", [
            'name' => 'Forbidden',
        ])->assertForbidden();
    }
}
