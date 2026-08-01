<?php

namespace Tests\Feature;

use App\Domains\Core\Models\Company;
use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Domains\KDS\Events\TicketStatusUpdated;
use App\Domains\KDS\Models\KitchenTicket;
use App\Domains\POS\Models\Order;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class KdsAccessTest extends TestCase
{
    use RefreshDatabase;

    public function test_kds_only_returns_active_tickets_from_the_users_company(): void
    {
        [$user, $outlet] = $this->companyContext('Tjoerah');
        [, $foreignOutlet] = $this->companyContext('Foreign');
        $active = $this->ticket($outlet, 'pending');
        $this->ticket($outlet, 'completed');
        $this->ticket($foreignOutlet, 'pending');

        $this->actingAs($user, 'api')
            ->getJson('/api/kds/tickets?station=kitchen')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $active->id);
    }

    public function test_user_cannot_update_a_ticket_from_another_company(): void
    {
        [$user] = $this->companyContext('Tjoerah');
        [, $foreignOutlet] = $this->companyContext('Foreign');
        $foreignTicket = $this->ticket($foreignOutlet, 'pending');

        $this->actingAs($user, 'api')
            ->postJson("/api/kds/tickets/{$foreignTicket->id}/status", [
                'status' => 'accepted',
            ])
            ->assertNotFound();

        $this->assertDatabaseHas('kitchen_tickets', [
            'id' => $foreignTicket->id,
            'status' => 'pending',
        ]);
    }

    public function test_ticket_status_event_uses_a_private_outlet_channel(): void
    {
        [, $outlet] = $this->companyContext('Tjoerah');
        $ticket = $this->ticket($outlet, 'accepted');
        $event = new TicketStatusUpdated($ticket);
        $channel = $event->broadcastOn();

        $this->assertInstanceOf(PrivateChannel::class, $channel);
        $this->assertSame("private-kds.outlet.{$outlet->id}", $channel->name);
        $this->assertSame('ticket.status.updated', $event->broadcastAs());
    }

    public function test_company_user_receives_all_active_outlets_for_realtime_subscriptions(): void
    {
        [$user, $outlet] = $this->companyContext('Tjoerah');
        $secondOutlet = Outlet::create([
            'company_id' => $outlet->company_id,
            'name' => 'Tjoerah Second Outlet',
            'code' => 'TJO2',
            'is_active' => true,
        ]);
        Outlet::create([
            'company_id' => $outlet->company_id,
            'name' => 'Tjoerah Closed Outlet',
            'code' => 'TJOC',
            'is_active' => false,
        ]);

        $response = $this->actingAs($user, 'api')
            ->getJson('/api/me')
            ->assertOk()
            ->assertJsonCount(2, 'user.outlets');

        $this->assertEqualsCanonicalizing(
            [$outlet->id, $secondOutlet->id],
            collect($response->json('user.outlets'))->pluck('id')->all(),
        );
    }

    private function companyContext(string $name): array
    {
        $company = Company::create(['name' => $name]);
        $outlet = Outlet::create([
            'company_id' => $company->id,
            'name' => "{$name} Outlet",
            'code' => strtoupper(substr($name, 0, 4)),
            'is_active' => true,
        ]);
        $user = User::factory()->create([
            'company_id' => $company->id,
            'role' => 'cashier',
        ]);

        return [$user, $outlet];
    }

    private function ticket(Outlet $outlet, string $status): KitchenTicket
    {
        $order = Order::create([
            'company_id' => $outlet->company_id,
            'outlet_id' => $outlet->id,
            'receipt_number' => 'RCP-'.fake()->unique()->numerify('######'),
            'status' => 'paid',
        ]);

        return KitchenTicket::create([
            'order_id' => $order->id,
            'outlet_id' => $outlet->id,
            'station' => 'kitchen',
            'status' => $status,
            'priority' => 'normal',
        ]);
    }
}
