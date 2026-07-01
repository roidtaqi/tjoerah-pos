<?php

namespace Database\Seeders;

use App\Domains\Core\Models\User;
use App\Domains\Core\Models\Outlet;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\Product;
use App\Domains\POS\Models\ModifierGroup;
use App\Domains\POS\Models\ModifierOption;
use App\Domains\POS\Models\ProductVariant;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // 1. Create Outlet & Owner
        $outlet = Outlet::create([
            'name' => 'Tjoerah Main Outlet',
            'address' => '123 Coffee Street, Jakarta',
            'phone' => '+6281234567890',
            'is_active' => true,
        ]);

        $owner = User::factory()->create([
            'name' => 'Owner Admin',
            'email' => 'owner@tjoerah.com',
            'password' => Hash::make('password'),
            'pin' => '1234',
            'role' => 'owner',
        ]);

        $owner->outlets()->attach($outlet->id);

        // 2. Create Catalog Data
        $catCoffee = Category::create(['name' => 'Coffee', 'is_active' => true]);
        $catNonCoffee = Category::create(['name' => 'Non-Coffee', 'is_active' => true]);

        // Product: Cappuccino
        $cappuccino = Product::create([
            'category_id' => $catCoffee->id,
            'name' => 'Cappuccino',
            'sku' => 'CAP-001',
            'base_price' => 35000,
            'is_active' => true,
        ]);

        // Variants for Cappuccino
        ProductVariant::create(['product_id' => $cappuccino->id, 'name' => 'Hot', 'additional_price' => 0]);
        ProductVariant::create(['product_id' => $cappuccino->id, 'name' => 'Iced', 'additional_price' => 5000]);

        // Modifiers for Coffee
        $sugarLevel = ModifierGroup::create([
            'name' => 'Sugar Level',
            'is_multiple_selection' => false,
            'is_required' => true,
        ]);

        ModifierOption::create(['modifier_group_id' => $sugarLevel->id, 'name' => 'Normal Sugar', 'additional_price' => 0]);
        ModifierOption::create(['modifier_group_id' => $sugarLevel->id, 'name' => 'Less Sugar', 'additional_price' => 0]);
        ModifierOption::create(['modifier_group_id' => $sugarLevel->id, 'name' => 'No Sugar', 'additional_price' => 0]);

        $extraShot = ModifierGroup::create([
            'name' => 'Extra Shot',
            'is_multiple_selection' => true,
            'is_required' => false,
        ]);

        ModifierOption::create(['modifier_group_id' => $extraShot->id, 'name' => 'Espresso Shot', 'additional_price' => 8000]);

        // Attach Modifiers to Cappuccino
        $cappuccino->modifierGroups()->attach([$sugarLevel->id, $extraShot->id]);

        // Product: Matcha Latte
        $matcha = Product::create([
            'category_id' => $catNonCoffee->id,
            'name' => 'Matcha Latte',
            'sku' => 'MAT-001',
            'base_price' => 38000,
            'is_active' => true,
        ]);
        
        $matcha->modifierGroups()->attach([$sugarLevel->id]);
    }
}
