<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\POS\Models\ModifierOption;
use App\Domains\POS\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CloudDeploymentTest extends TestCase
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

    public function test_github_pages_origin_can_preflight_the_login_endpoint(): void
    {
        config()->set('cors.allowed_origins', ['https://roidtaqi.github.io']);

        $response = $this->call('OPTIONS', '/api/auth/pin/login', server: [
            'HTTP_ORIGIN' => 'https://roidtaqi.github.io',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'content-type',
        ]);

        $response
            ->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', 'https://roidtaqi.github.io')
            ->assertHeader('Access-Control-Allow-Methods');
    }

    public function test_flutter_web_localhost_origin_can_use_a_random_port(): void
    {
        config()->set('cors.allowed_origins', ['https://roidtaqi.github.io']);
        config()->set('cors.allowed_origins_patterns', [
            '#^https?://(localhost|127\.0\.0\.1)(:\d+)?$#',
        ]);

        $response = $this->call('OPTIONS', '/api/auth/pin/login', server: [
            'HTTP_ORIGIN' => 'http://localhost:54321',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'content-type',
        ]);

        $response
            ->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', 'http://localhost:54321')
            ->assertHeader('Access-Control-Allow-Methods');
    }
}
