<?php

namespace Tests\Feature;

use App\Domains\Core\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_login_with_email_and_password(): void
    {
        $user = User::factory()->create([
            'email' => 'owner@tjoerah.com',
            'password' => Hash::make('password'),
            'pin' => '1234',
            'role' => 'owner',
        ]);

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $response
            ->assertOk()
            ->assertJsonPath('user.email', $user->email)
            ->assertJsonPath('user.role', 'owner')
            ->assertJsonStructure(['token', 'token_type', 'expires_in']);
        $this->assertArrayNotHasKey('pin', $response->json('user'));
    }

    public function test_user_can_login_with_pin(): void
    {
        $user = User::factory()->create(['pin' => '1234']);

        $response = $this->postJson('/api/auth/pin/login', ['pin' => '1234']);

        $response
            ->assertOk()
            ->assertJsonPath('user.email', $user->email)
            ->assertJsonStructure(['token']);
        $this->assertArrayNotHasKey('pin', $response->json('user'));
    }

    public function test_invalid_email_and_pin_return_unauthorized(): void
    {
        User::factory()->create([
            'email' => 'owner@tjoerah.com',
            'password' => Hash::make('password'),
            'pin' => '1234',
        ]);

        $this->postJson('/api/auth/login', [
            'email' => 'owner@tjoerah.com',
            'password' => 'wrong-password',
        ])->assertUnauthorized();

        $this->postJson('/api/auth/pin/login', [
            'pin' => '9999',
        ])->assertUnauthorized();
    }
}
