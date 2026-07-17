<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\POS\Models\ModifierOption;
use App\Domains\POS\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LocalSetupTest extends TestCase
{
    use RefreshDatabase;

    public function test_demo_seeder_can_run_repeatedly_without_duplicate_data(): void
    {
        $this->seed();

        $counts = [
            'users' => User::count(),
            'outlets' => Outlet::count(),
            'products' => Product::count(),
            'modifier_options' => ModifierOption::count(),
        ];

        $this->seed();

        $this->assertSame($counts, [
            'users' => User::count(),
            'outlets' => Outlet::count(),
            'products' => Product::count(),
            'modifier_options' => ModifierOption::count(),
        ]);
    }

    public function test_flutter_web_localhost_can_preflight_the_login_endpoint(): void
    {
        config()->set('cors.allowed_origins', ['*']);

        $response = $this->call('OPTIONS', '/api/auth/pin/login', server: [
            'HTTP_ORIGIN' => 'http://localhost:54321',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'content-type',
        ]);

        $response
            ->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', '*')
            ->assertHeader('Access-Control-Allow-Methods');
    }
}
