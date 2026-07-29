<?php

namespace App\Domains\Inventory\Services;

use App\Domains\Core\Models\User;
use App\Domains\Inventory\Models\Warehouse;
use App\Domains\Inventory\Models\Wastage;
use App\Domains\KDS\Events\TicketStatusUpdated;
use App\Domains\KDS\Models\KitchenTicket;
use App\Domains\POS\Models\OrderItem;
use App\Domains\Recipe\Models\Recipe;
use App\Domains\Recipe\Models\RecipeVersion;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Throwable;

class ProductionIncidentService
{
    public function record(
        OrderItem $orderItem,
        int $quantity,
        string $resolution,
        string $reason,
        ?User $user,
        ?KitchenTicket $ticket = null,
    ): Wastage {
        $orderItem->loadMissing('order.outlet');
        $order = $orderItem->order;
        if (! $order) {
            throw ValidationException::withMessages([
                'order_item_id' => 'Pesanan untuk produk ini tidak ditemukan.',
            ]);
        }

        $recipe = Recipe::query()
            ->where('product_id', $orderItem->product_id)
            ->where('status', 'active')
            ->when(
                $order->outlet?->company_id,
                fn ($query, $companyId) => $query->where('company_id', $companyId),
            )
            ->first();
        $version = $recipe
            ? RecipeVersion::with('items')
                ->where('recipe_id', $recipe->id)
                ->where('version', $recipe->active_version)
                ->first()
            : null;

        if ($resolution === 'remake' && (! $recipe || ! $version)) {
            throw ValidationException::withMessages([
                'order_item_id' => 'Resep aktif diperlukan sebelum produk dapat dibuat ulang.',
            ]);
        }

        $warehouse = $resolution === 'remake'
            ? Warehouse::where('outlet_id', $order->outlet_id)
                ->where('is_active', true)
                ->first()
            : null;
        if ($resolution === 'remake' && ! $warehouse) {
            throw ValidationException::withMessages([
                'warehouse' => 'Gudang aktif outlet belum tersedia.',
            ]);
        }

        $unitWasteValue = $recipe
            ? (float) $recipe->current_cost
            : ((float) $orderItem->cogs_total / max((int) $orderItem->qty, 1));
        $wasteValue = $unitWasteValue * $quantity;

        $wastage = DB::transaction(function () use (
            $order,
            $orderItem,
            $quantity,
            $resolution,
            $reason,
            $user,
            $recipe,
            $version,
            $warehouse,
            $wasteValue,
            $ticket,
        ) {
            $wastage = Wastage::create([
                'outlet_id' => $order->outlet_id,
                'order_id' => $order->id,
                'order_item_id' => $orderItem->id,
                'product_id' => $orderItem->product_id,
                'user_id' => $user?->id,
                'waste_type' => 'wrong_production',
                'resolution' => $resolution,
                'recipe_version' => $recipe?->active_version,
                'original_stock_consumed' => true,
                'quantity' => $quantity,
                'value' => $wasteValue,
                'reason' => $reason,
            ]);

            if ($resolution === 'remake' && $recipe && $version && $warehouse) {
                $yieldQuantity = max((float) $recipe->yield_quantity, 0.0001);
                foreach ($version->items as $recipeItem) {
                    if (! $recipeItem->inventory_item_id) {
                        continue;
                    }
                    $ingredientQuantity = ((float) $recipeItem->quantity / $yieldQuantity) * $quantity;
                    InventoryService::recordMovement(
                        itemId: $recipeItem->inventory_item_id,
                        warehouseId: $warehouse->id,
                        quantity: -$ingredientQuantity,
                        type: 'remake',
                        unitCost: (float) $recipeItem->unit_cost,
                        referenceType: Wastage::class,
                        referenceId: $wastage->id,
                        referenceNumber: $order->receipt_number,
                        reason: "Remake {$orderItem->snapshot_name}: {$reason}",
                        userId: $user?->id,
                    );
                }

                $orderItem->increment('cogs_total', $wasteValue);
                $order->refresh();
                $totalCogs = (float) $order->items()->sum('cogs_total');
                $netSales = (float) $order->subtotal - (float) $order->discount_total;
                $order->update([
                    'cogs_total' => $totalCogs,
                    'gross_profit' => $netSales - $totalCogs,
                ]);

                if ($ticket) {
                    $ticket->update([
                        'status' => 'preparing',
                        'preparing_at' => now(),
                        'ready_at' => null,
                        'completed_at' => null,
                    ]);
                }
            }

            return $wastage;
        });

        if ($ticket && $resolution === 'remake') {
            try {
                event(new TicketStatusUpdated($ticket->fresh()));
            } catch (Throwable $exception) {
                Log::warning('Production remake was saved but could not be broadcast to KDS.', [
                    'ticket_id' => $ticket->id,
                    'error' => $exception->getMessage(),
                ]);
            }
        }

        return $wastage;
    }
}
