<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\Employee\Models\AttendanceShift;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class EmployeeManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_update_and_deactivate_employee_account(): void
    {
        [$company, $outlet, $owner, $shift] = $this->context();
        $this->actingAs($owner, 'api');
        User::factory()->create(['company_id' => $company->id, 'pin' => '2468']);

        $this->getJson('/api/employees/options')
            ->assertOk()
            ->assertJsonCount(6, 'roles')
            ->assertJsonPath('outlets.0.id', $outlet->id);

        $employee = $this->postJson('/api/employees', [
            'outlet_id' => $outlet->id,
            'attendance_shift_id' => $shift->id,
            'employee_number' => 'EMP-001',
            'name' => 'Ayu Lestari',
            'phone' => '081234567890',
            'username' => 'ayu.lestari',
            'email' => 'ayu@tjoerah.test',
            'password' => 'rahasia123',
            'pin' => '2468',
            'role' => 'cashier',
            'position' => 'Kasir',
            'employment_status' => 'permanent',
            'hire_date' => '2026-07-29',
            'birth_date' => '2000-02-03',
            'gender' => 'female',
            'address' => 'Denpasar',
            'emergency_contact_name' => 'Wayan',
            'emergency_contact_phone' => '081200000001',
            'is_active' => true,
        ])->assertCreated()
            ->assertJsonPath('user.role', 'cashier')
            ->assertJsonPath('user.roles.0.slug', 'cashier')
            ->assertJsonCount(1, 'user.roles')
            ->assertJsonPath('attendance_shift.id', $shift->id)
            ->assertJsonPath('employment_status', 'permanent')
            ->json();

        $this->assertDatabaseHas('users', [
            'company_id' => $company->id,
            'username' => 'ayu.lestari',
            'email' => 'ayu@tjoerah.test',
            'phone' => '6281234567890',
            'role' => 'cashier',
            'is_active' => true,
        ]);
        $this->postJson('/api/auth/pin/login', [
            'identifier' => 'ayu.lestari',
            'pin' => '2468',
        ])
            ->assertOk()
            ->assertJsonPath('user.role', 'cashier')
            ->assertJsonCount(1, 'user.roles');

        $this->actingAs($owner, 'api')
            ->patchJson("/api/employees/{$employee['id']}", [
                'role' => 'barista',
                'position' => 'Barista',
                'is_active' => false,
            ])
            ->assertOk()
            ->assertJsonPath('user.role', 'barista')
            ->assertJsonCount(1, 'user.roles')
            ->assertJsonPath('is_active', false);

        $this->postJson('/api/auth/pin/login', [
            'identifier' => 'ayu.lestari',
            'pin' => '2468',
        ])
            ->assertUnauthorized();
    }

    public function test_admin_cannot_assign_admin_and_cashier_cannot_manage_employees(): void
    {
        [$company, $outlet, , $shift] = $this->context();
        $admin = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'admin',
        ]);
        $cashier = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'cashier',
        ]);
        $payload = [
            'outlet_id' => $outlet->id,
            'attendance_shift_id' => $shift->id,
            'employee_number' => 'EMP-002',
            'name' => 'Budi',
            'email' => 'budi@tjoerah.test',
            'password' => 'rahasia123',
            'pin' => '1357',
            'role' => 'admin',
            'employment_status' => 'contract',
            'is_active' => true,
        ];

        $this->actingAs($admin, 'api')
            ->getJson('/api/employees/options')
            ->assertOk()
            ->assertJsonPath('roles.0.value', 'admin')
            ->assertJsonPath('roles.0.assignable', false);
        $this
            ->postJson('/api/employees', $payload)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('role');

        $this->actingAs($cashier, 'api')
            ->getJson('/api/employees')
            ->assertForbidden();
        $this->postJson('/api/employees', [
            ...$payload,
            'role' => 'cashier',
        ])->assertForbidden();
        $this->assertDatabaseCount('employees', 0);
    }

    private function context(): array
    {
        $company = Company::create(['name' => 'Tjoerah']);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'name' => 'Renon',
            'code' => 'RNN',
        ]);
        $owner = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'owner',
        ]);
        $owner->outlets()->attach($outlet);
        $shift = AttendanceShift::create([
            'company_id' => $company->id,
            'outlet_id' => $outlet->id,
            'name' => 'Shift Pagi',
            'start_time' => '07:30',
            'late_after_time' => '07:45',
            'end_time' => '15:30',
            'check_in_open_minutes' => 60,
            'is_active' => true,
            'sort_order' => 1,
        ]);

        return [$company, $outlet, $owner, $shift];
    }
}
