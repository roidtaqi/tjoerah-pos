<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Brand;
use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TableManagementApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_manager_can_configure_areas_and_tables(): void
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
            'name' => 'Main Outlet',
            'code' => 'MAIN',
        ]);
        $manager = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'outlet_manager',
        ]);
        $this->actingAs($manager, 'api');

        $floor = $this->postJson('/api/floors', [
            'outlet_id' => $outlet->id,
            'name' => 'Teras',
            'sort_order' => 1,
        ])->assertCreated()->json();

        $table = $this->postJson('/api/tables', [
            'outlet_id' => $outlet->id,
            'floor_id' => $floor['id'],
            'name' => 'Meja 01',
            'capacity' => 4,
            'status' => 'available',
            'position_x' => 32,
            'position_y' => 48,
        ])->assertCreated()->json();

        $this->patchJson("/api/tables/{$table['id']}", [
            'name' => 'Meja Teras 01',
            'capacity' => 6,
            'position_x' => 80,
            'position_y' => 96,
        ])->assertOk()
            ->assertJsonPath('name', 'Meja Teras 01')
            ->assertJsonPath('capacity', 6);

        $this->deleteJson("/api/floors/{$floor['id']}")
            ->assertUnprocessable();
        $this->deleteJson("/api/tables/{$table['id']}")->assertNoContent();
        $this->deleteJson("/api/floors/{$floor['id']}")->assertNoContent();
    }
}
