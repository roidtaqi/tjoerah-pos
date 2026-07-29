<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\User;
use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\POS\Models\Product;
use App\Domains\Recipe\Models\Recipe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class RecipeManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_and_version_recipe_using_server_inventory_cost(): void
    {
        [$company, $owner, $product, $ingredient] = $this->recipeContext();
        $this->actingAs($owner, 'api');

        $recipe = $this->postJson('/api/recipes', [
            'company_id' => Company::create(['name' => 'Spoofed Company'])->id,
            'product_id' => $product->id,
            'name' => 'Kopi Susu',
            'status' => 'active',
            'yield_quantity' => 2,
            'yield_unit' => 'porsi',
            'items' => [
                [
                    'inventory_item_id' => $ingredient->id,
                    'quantity' => 10,
                    'waste_percent' => 5,
                    'unit_cost' => 1,
                ],
            ],
        ])->assertCreated()
            ->assertJsonPath('company_id', $company->id)
            ->assertJsonPath('active_version', 1)
            ->assertJsonPath('items.0.inventory_item_name', 'Biji Kopi')
            ->assertJsonPath('items.0.unit_cost', '100.0000')
            ->assertJsonPath('items.0.total_cost', '1050.0000')
            ->assertJsonPath('current_cost', '525.0000')
            ->json();

        $this->patchJson("/api/recipes/{$recipe['id']}", [
            'product_id' => $product->id,
            'name' => 'Kopi Susu Signature',
            'status' => 'active',
            'yield_quantity' => 2,
            'yield_unit' => 'porsi',
            'items' => [
                [
                    'inventory_item_id' => $ingredient->id,
                    'quantity' => 12,
                    'waste_percent' => 0,
                ],
            ],
        ])->assertOk()
            ->assertJsonPath('name', 'Kopi Susu Signature')
            ->assertJsonPath('active_version', 2)
            ->assertJsonCount(1, 'items')
            ->assertJsonCount(2, 'versions')
            ->assertJsonPath('items.0.quantity', '12.0000')
            ->assertJsonPath('current_cost', '600.0000');

        $this->assertDatabaseCount('recipe_versions', 2);
        $this->assertDatabaseCount('recipe_items', 2);
    }

    public function test_recipe_lists_and_mutations_are_scoped_to_user_company(): void
    {
        [$company, $owner, $product, $ingredient] = $this->recipeContext();
        $otherCompany = Company::create(['name' => 'Other Company']);
        $otherRecipe = Recipe::create([
            'company_id' => $otherCompany->id,
            'name' => 'Private Recipe',
        ]);

        $this->actingAs($owner, 'api')
            ->postJson('/api/recipes', [
                'product_id' => $product->id,
                'name' => 'Visible Recipe',
                'status' => 'draft',
                'yield_quantity' => 1,
                'yield_unit' => 'porsi',
                'items' => [
                    [
                        'inventory_item_id' => $ingredient->id,
                        'quantity' => 1,
                        'waste_percent' => 0,
                    ],
                ],
            ])
            ->assertCreated();

        $this->getJson('/api/recipes')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.company_id', $company->id);

        $this->patchJson("/api/recipes/{$otherRecipe->id}", [
            'name' => 'Changed',
        ])->assertNotFound();
        $this->deleteJson("/api/recipes/{$otherRecipe->id}")
            ->assertNotFound();
    }

    public function test_cashier_cannot_mutate_recipes(): void
    {
        [$company, , $product, $ingredient] = $this->recipeContext();
        $cashier = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'cashier',
        ]);
        $recipe = Recipe::create([
            'company_id' => $company->id,
            'name' => 'Protected Recipe',
        ]);
        $payload = [
            'product_id' => $product->id,
            'name' => 'Forbidden Recipe',
            'status' => 'draft',
            'yield_quantity' => 1,
            'yield_unit' => 'porsi',
            'items' => [
                [
                    'inventory_item_id' => $ingredient->id,
                    'quantity' => 1,
                ],
            ],
        ];

        $this->actingAs($cashier, 'api');
        $this->postJson('/api/recipes', $payload)->assertForbidden();
        $this->patchJson("/api/recipes/{$recipe->id}", $payload)
            ->assertForbidden();
        $this->deleteJson("/api/recipes/{$recipe->id}")
            ->assertForbidden();
    }

    public function test_owner_can_soft_delete_recipe(): void
    {
        [, $owner, $product, $ingredient] = $this->recipeContext();
        $this->actingAs($owner, 'api');

        $recipeId = $this->postJson('/api/recipes', [
            'product_id' => $product->id,
            'name' => 'Temporary Recipe',
            'status' => 'inactive',
            'yield_quantity' => 1,
            'yield_unit' => 'porsi',
            'items' => [
                [
                    'inventory_item_id' => $ingredient->id,
                    'quantity' => 1,
                    'waste_percent' => 0,
                ],
            ],
        ])->assertCreated()->json('id');

        $this->deleteJson("/api/recipes/{$recipeId}")->assertNoContent();
        $this->assertSoftDeleted('recipes', ['id' => $recipeId]);
        $this->assertDatabaseHas('recipe_versions', ['recipe_id' => $recipeId]);
    }

    public function test_owner_can_download_and_import_recipe_csv_template(): void
    {
        [$company, $owner, $product, $ingredient] = $this->recipeContext();
        $secondIngredient = InventoryItem::create([
            'company_id' => $company->id,
            'name' => 'Susu Segar',
            'sku' => 'MILK-01',
            'unit' => 'ml',
            'weighted_average_cost' => 50,
            'is_active' => true,
        ]);
        $this->actingAs($owner, 'api');

        $template = $this->get('/api/recipes/template')
            ->assertOk()
            ->assertHeader('content-type', 'text/csv; charset=UTF-8');
        $this->assertStringContainsString(
            'recipe_name',
            $template->streamedContent(),
        );

        $csv = implode("\n", [
            'recipe_name;product_name;status;yield_quantity;yield_unit;ingredient_name;ingredient_sku;quantity;unit;waste_percent;notes',
            "Kopi Susu Batch;{$product->name};active;2;porsi;{$ingredient->name};{$ingredient->sku};10;g;0;",
            "Kopi Susu Batch;{$product->name};active;2;porsi;{$secondIngredient->name};{$secondIngredient->sku};20;ml;0;",
        ]);

        $this->post('/api/recipes/import', [
            'file' => UploadedFile::fake()->createWithContent(
                'resep.csv',
                $csv,
            ),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('imported_recipes', 1)
            ->assertJsonPath('created', 1);

        $recipe = Recipe::where('product_id', $product->id)->firstOrFail();
        $this->assertSame('active', $recipe->status);
        $this->assertSame(1000.0, (float) $recipe->current_cost);
        $this->assertCount(2, $recipe->latestVersionRecord->items);
    }

    private function recipeContext(): array
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $product = Product::create([
            'company_id' => $company->id,
            'name' => 'Kopi Susu',
            'base_price' => 25000,
        ]);
        $ingredient = InventoryItem::create([
            'company_id' => $company->id,
            'name' => 'Biji Kopi',
            'sku' => 'BEAN-01',
            'unit' => 'g',
            'weighted_average_cost' => 100,
            'is_active' => true,
        ]);

        return [$company, $owner, $product, $ingredient];
    }
}
