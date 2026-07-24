<?php

namespace Database\Seeders;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendancePolicy;
use App\Domains\Employee\Models\AttendanceShift;
use App\Domains\Employee\Models\Employee;
use App\Domains\POS\Models\Category;
use App\Domains\POS\Models\ModifierGroup;
use App\Domains\POS\Models\ModifierOption;
use App\Domains\POS\Models\Product;
use App\Domains\POS\Models\ProductVariant;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use RuntimeException;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $demoCredentials = $this->demoCredentials();
        $outlet = Outlet::firstOrCreate([
            'name' => 'Tjoerah Main Outlet',
        ], [
            'address' => '123 Coffee Street, Jakarta',
            'phone' => '+6281234567890',
            'is_active' => true,
        ]);

        $owner = User::updateOrCreate(
            ['email' => 'owner@tjoerah.com'],
            [
                'name' => 'Owner Admin',
                'password' => Hash::make($demoCredentials['owner_password']),
                'pin' => $demoCredentials['owner_pin'],
                'role' => 'owner',
            ],
        );

        $owner->outlets()->syncWithoutDetaching([$outlet->id]);

        $cashier = User::updateOrCreate(
            ['email' => 'cashier@tjoerah.com'],
            [
                'name' => 'Kasir Demo',
                'password' => Hash::make($demoCredentials['cashier_password']),
                'pin' => $demoCredentials['cashier_pin'],
                'role' => 'cashier',
            ],
        );

        $cashier->outlets()->syncWithoutDetaching([$outlet->id]);

        $attendanceShifts = collect([
            [
                'name' => 'Shift Pagi',
                'start_time' => '07:30',
                'late_after_time' => '07:45',
                'end_time' => '15:30',
                'sort_order' => 1,
            ],
            [
                'name' => 'Shift Kedua',
                'start_time' => '15:30',
                'late_after_time' => '15:45',
                'end_time' => '23:30',
                'sort_order' => 2,
            ],
        ])->map(fn (array $data) => AttendanceShift::updateOrCreate(
            [
                'outlet_id' => $outlet->id,
                'name' => $data['name'],
            ],
            [
                ...$data,
                'company_id' => $outlet->company_id,
                'check_in_open_minutes' => 60,
                'is_active' => true,
            ],
        ))->values();

        foreach ([$owner, $cashier] as $index => $user) {
            $employee = Employee::firstOrCreate(
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
            if (! $employee->attendance_shift_id) {
                $employee->update([
                    'attendance_shift_id' => $attendanceShifts[$index]->id,
                ]);
            }
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

    /**
     * @return array{
     *     owner_password: string,
     *     owner_pin: string,
     *     cashier_password: string,
     *     cashier_pin: string
     * }
     */
    private function demoCredentials(): array
    {
        $credentials = [
            'owner_password' => env('DEMO_OWNER_PASSWORD') ?: 'password',
            'owner_pin' => env('DEMO_OWNER_PIN') ?: '1234',
            'cashier_password' => env('DEMO_CASHIER_PASSWORD') ?: 'password',
            'cashier_pin' => env('DEMO_CASHIER_PIN') ?: '5678',
        ];

        if (app()->isProduction() && (
            $credentials['owner_password'] === 'password'
            || $credentials['cashier_password'] === 'password'
            || $credentials['owner_pin'] === '1234'
            || $credentials['cashier_pin'] === '5678'
        )) {
            throw new RuntimeException(
                'Set custom DEMO_OWNER_PASSWORD, DEMO_OWNER_PIN, '
                .'DEMO_CASHIER_PASSWORD, and DEMO_CASHIER_PIN before seeding production.',
            );
        }

        return $credentials;
    }
}
