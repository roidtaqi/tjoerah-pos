<?php

namespace Database\Seeders;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\Employee;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\ModifierGroup;
use App\Domains\POS\Models\ModifierOption;
use App\Domains\POS\Models\Product;
use App\Domains\POS\Models\ProductVariant;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $outlet = Outlet::firstOrCreate([
            'name' => 'Tjoerah Main Outlet',
        ], [
            'address' => '123 Coffee Street, Jakarta',
            'phone' => '+6281234567890',
            'is_active' => true,
        ]);

        $owner = User::where('email', 'owner@tjoerah.com')->first();
        if (! $owner) {
            $owner = User::create([
                'name' => 'Owner Admin',
                'email' => 'owner@tjoerah.com',
                'password' => Hash::make('password'),
                'pin' => '1234',
                'role' => 'owner',
            ]);
        }

        $owner->outlets()->syncWithoutDetaching([$outlet->id]);

        $cashier = User::where('email', 'cashier@tjoerah.com')->first();
        if (! $cashier) {
            $cashier = User::create([
                'name' => 'Kasir Demo',
                'email' => 'cashier@tjoerah.com',
                'password' => Hash::make('password'),
                'pin' => '5678',
                'role' => 'cashier',
            ]);
        }

        $cashier->outlets()->syncWithoutDetaching([$outlet->id]);

        foreach ([$owner, $cashier] as $user) {
            Employee::firstOrCreate(
                ['user_id' => $user->id],
                [
                    'company_id' => $user->company_id ?? $outlet->company_id,
                    'outlet_id' => $outlet->id,
                    'employee_number' => 'USR-'.str_pad((string) $user->id, 4, '0', STR_PAD_LEFT),
                    'name' => $user->name,
                    'email' => $user->email,
                    'position' => $user->role,
                    'hire_date' => now()->toDateString(),
                    'is_active' => true,
                ],
            );
        }

        AttendancePolicy::firstOrCreate(
            ['outlet_id' => $outlet->id],
            [
                'company_id' => $outlet->company_id,
                'timezone' => $outlet->timezone ?: 'Asia/Makassar',
                'work_start_time' => '08:00',
                'work_end_time' => '17:00',
                'late_tolerance_minutes' => 10,
            ],
        );

        $catCoffee = Category::firstOrCreate(['name' => 'Coffee'], ['is_active' => true]);
        $catNonCoffee = Category::firstOrCreate(['name' => 'Non-Coffee'], ['is_active' => true]);

        $cappuccino = Product::firstOrCreate([
            'sku' => 'CAP-001',
        ], [
            'category_id' => $catCoffee->id,
            'name' => 'Cappuccino',
            'base_price' => 35000,
            'is_active' => true,
        ]);

        ProductVariant::firstOrCreate(
            ['product_id' => $cappuccino->id, 'name' => 'Hot'],
            ['additional_price' => 0],
        );
        ProductVariant::firstOrCreate(
            ['product_id' => $cappuccino->id, 'name' => 'Iced'],
            ['additional_price' => 5000],
        );

        $sugarLevel = ModifierGroup::firstOrCreate([
            'name' => 'Sugar Level',
        ], [
            'is_multiple_selection' => false,
            'is_required' => true,
        ]);

        foreach (['Normal Sugar', 'Less Sugar', 'No Sugar'] as $name) {
            ModifierOption::firstOrCreate(
                ['modifier_group_id' => $sugarLevel->id, 'name' => $name],
                ['additional_price' => 0],
            );
        }

        $extraShot = ModifierGroup::firstOrCreate([
            'name' => 'Extra Shot',
        ], [
            'is_multiple_selection' => true,
            'is_required' => false,
        ]);

        ModifierOption::firstOrCreate(
            ['modifier_group_id' => $extraShot->id, 'name' => 'Espresso Shot'],
            ['additional_price' => 8000],
        );

        $cappuccino->modifierGroups()->syncWithoutDetaching([$sugarLevel->id, $extraShot->id]);

        $matcha = Product::firstOrCreate([
            'sku' => 'MAT-001',
        ], [
            'category_id' => $catNonCoffee->id,
            'name' => 'Matcha Latte',
            'base_price' => 38000,
            'is_active' => true,
        ]);

        $matcha->modifierGroups()->syncWithoutDetaching([$sugarLevel->id]);
    }
}
