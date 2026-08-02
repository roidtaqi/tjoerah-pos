<?php

namespace Tests\Feature;

use App\Domains\Core\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_login_with_any_identifier_and_password(): void
    {
        $user = User::factory()->create([
            'username' => 'owner.renon',
            'email' => 'owner@tjoerah.com',
            'phone' => '6281234567890',
            'password' => Hash::make('password'),
            'pin' => '1234',
            'role' => 'owner',
        ]);

        foreach ([$user->email, 'OWNER.RENON', '081234567890'] as $identifier) {
            $response = $this->postJson('/api/auth/login', [
                'identifier' => $identifier,
                'password' => 'password',
            ]);

            $response
                ->assertOk()
                ->assertJsonPath('user.email', $user->email)
                ->assertJsonPath('user.role', 'owner')
                ->assertJsonStructure(['token', 'token_type', 'expires_in']);
            $this->assertArrayNotHasKey('pin', $response->json('user'));
        }

        $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'password',
        ])->assertOk();
    }

    public function test_pin_login_uses_identifier_to_disambiguate_duplicate_pins(): void
    {
        $owner = User::factory()->create([
            'username' => 'owner',
            'email' => 'owner@tjoerah.com',
            'phone' => '6281234567890',
            'pin' => '1234',
        ]);
        $cashier = User::factory()->create([
            'username' => 'cashier',
            'email' => 'cashier@tjoerah.com',
            'phone' => '6281234567891',
            'pin' => '1234',
        ]);

        $this->postJson('/api/auth/pin/login', [
            'identifier' => 'owner',
            'pin' => '1234',
        ])->assertOk()
            ->assertJsonPath('user.id', $owner->id)
            ->assertJsonStructure(['token']);

        $response = $this->postJson('/api/auth/pin/login', [
            'identifier' => '081234567891',
            'pin' => '1234',
        ])->assertOk()
            ->assertJsonPath('user.id', $cashier->id);
        $this->assertArrayNotHasKey('pin', $response->json('user'));

        $this->postJson('/api/auth/pin/login', ['pin' => '1234'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('identifier');
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
            'identifier' => 'owner@tjoerah.com',
            'pin' => '9999',
        ])->assertUnauthorized();
    }

    public function test_ambiguous_identifier_never_selects_the_first_account(): void
    {
        User::factory()->create([
            'username' => '6281234567890',
            'phone' => '6281111111111',
            'pin' => '1234',
        ]);
        User::factory()->create([
            'username' => 'second-user',
            'phone' => '6281234567890',
            'pin' => '1234',
        ]);

        $this->postJson('/api/auth/pin/login', [
            'identifier' => '6281234567890',
            'pin' => '1234',
        ])->assertUnauthorized();
    }
}
