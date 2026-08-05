<?php

namespace App\Domains\Sales\Services;

use App\Domains\Core\Models\User;
use App\Domains\CRM\Models\Customer;
use App\Domains\Inventory\Models\StockMovement;
use App\Domains\Inventory\Services\InventoryService;
use App\Domains\KDS\Events\TicketStatusUpdated;
use App\Domains\POS\Models\DiningTable;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\Refund;
use App\Domains\POS\Models\TableSession;
use App\Domains\POS\Models\VoidTransaction;
use App\Domains\POS\Services\CashLedgerService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Throwable;

class OrderCancellationService
{
    public function __construct(private CashLedgerService $cashLedgerService) {}

    /**
     * @return array{order: Order, void: VoidTransaction, refund: ?Refund}
     */
    public function cancel(
        Order $order,
        User $user,
        string $reason,
        string $inventoryOutcome,
    ): array {
        $cancelledTicketIds = [];

        $result = DB::transaction(function () use (
            $order,
            $user,
            $reason,
            $inventoryOutcome,
            &$cancelledTicketIds,
        ) {
            $locked = Order::query()
                ->with(['items', 'payments', 'refunds', 'kitchenTickets.items'])
                ->lockForUpdate()
                ->findOrFail($order->id);

            if ($locked->status === 'voided') {
                throw ValidationException::withMessages([
                    'order' => 'Pesanan ini sudah dibatalkan.',
                ]);
            }

            if (! in_array($locked->status, [
                'draft',
                'open',
                'held',
                'paid',
                'completed',
                'partially_refunded',
                'refunded',
            ], true)) {
                throw ValidationException::withMessages([
                    'order' => 'Status pesanan ini tidak dapat dibatalkan.',
                ]);
            }

            $previousStatus = $locked->status;
            $approvedRefundAmount = (float) $locked->refunds
                ->where('status', 'approved')
                ->sum('amount');
            $completedPayments = $locked->payments->where('status', 'completed');
            $paidAmount = (float) $completedPayments->sum('amount');
            $refundableAmount = max(
                min((float) $locked->total, $paidAmount) - $approvedRefundAmount,
                0,
            );

            $refund = null;
            if ($refundableAmount > 0.009) {
                $refundMethod = $completedPayments
                    ->pluck('method')
                    ->map(fn ($method) => strtolower((string) $method))
                    ->unique()
                    ->count() === 1
                    ? $completedPayments->first()?->method
                    : 'mixed';
                $refund = Refund::create([
                    'order_id' => $locked->id,
                    'payment_id' => $completedPayments->last()?->id,
                    'user_id' => $user->id,
                    'amount' => $refundableAmount,
                    'type' => $approvedRefundAmount + $refundableAmount >= (float) $locked->total
                        ? 'full'
                        : 'partial',
                    'inventory_outcome' => 'no_stock_return',
                    'reason' => "Pembatalan pesanan: {$reason}",
                    'status' => 'approved',
                    'method' => $refundMethod,
                ]);
                $this->cashLedgerService->recordRefund($refund, $locked, $refundMethod);
            }

            $void = VoidTransaction::create([
                'order_id' => $locked->id,
                'user_id' => $user->id,
                'amount' => $locked->total,
                'previous_status' => $previousStatus,
                'inventory_outcome' => $inventoryOutcome,
                'refund_id' => $refund?->id,
                'reason' => $reason,
                'meta' => [
                    'approved_refund_before' => $approvedRefundAmount,
                    'refund_created' => $refundableAmount,
                    'original_cogs_total' => (float) $locked->cogs_total,
                ],
            ]);

            if ($inventoryOutcome === 'restore_stock') {
                $this->restoreOriginalInventory($locked, $void, $user);
                $void->update(['stock_restored_at' => now()]);
                $locked->items()->update(['cogs_total' => 0]);
                $locked->cogs_total = 0;
                $locked->gross_profit = 0;
            }

            foreach ($locked->kitchenTickets as $ticket) {
                $ticket->items()->update(['status' => 'cancelled']);
                $ticket->update([
                    'status' => 'cancelled',
                    'completed_at' => now(),
                ]);
                $cancelledTicketIds[] = $ticket->id;
            }

            $this->releaseTable($locked);
            if ($paidAmount > 0 && $locked->customer_id) {
                $this->reverseCustomerStatistics($locked);
            }

            $meta = $locked->meta ?? [];
            $meta['cancellation'] = [
                'void_transaction_id' => $void->id,
                'previous_status' => $previousStatus,
                'reason' => $reason,
                'inventory_outcome' => $inventoryOutcome,
                'refunded_amount' => $refundableAmount,
                'cancelled_by' => $user->id,
                'cancelled_at' => now()->toIso8601String(),
            ];
            $locked->status = 'voided';
            $locked->meta = $meta;
            $locked->save();

            return [
                'order' => $locked->fresh()->load([
                    'items',
                    'payments',
                    'refunds',
                    'kitchenTickets.items',
                ]),
                'void' => $void->fresh(),
                'refund' => $refund?->fresh(),
            ];
        });

        foreach ($cancelledTicketIds as $ticketId) {
            try {
                $ticket = $result['order']->kitchenTickets->firstWhere('id', $ticketId);
                if ($ticket) {
                    event(new TicketStatusUpdated($ticket));
                }
            } catch (Throwable $exception) {
                Log::warning('Order was cancelled but the KDS update could not be broadcast.', [
                    'order_id' => $order->id,
                    'ticket_id' => $ticketId,
                    'error' => $exception->getMessage(),
                ]);
            }
        }

        return $result;
    }

    private function restoreOriginalInventory(
        Order $order,
        VoidTransaction $void,
        User $user,
    ): void {
        $movements = StockMovement::query()
            ->where('reference_type', Order::class)
            ->where('reference_id', $order->id)
            ->where('movement_type', 'consume')
            ->where('quantity', '<', 0)
            ->get();

        foreach ($movements as $movement) {
            InventoryService::recordMovement(
                itemId: $movement->inventory_item_id,
                warehouseId: $movement->warehouse_id,
                quantity: abs((float) $movement->quantity),
                type: 'void_return',
                unitCost: (float) $movement->unit_cost,
                referenceType: VoidTransaction::class,
                referenceId: $void->id,
                referenceNumber: $order->receipt_number,
                reason: "Pembatalan {$order->receipt_number}: {$void->reason}",
                userId: $user->id,
            );
        }
    }

    private function releaseTable(Order $order): void
    {
        if (! $order->table_id) {
            return;
        }

        $closed = TableSession::query()
            ->where('table_id', $order->table_id)
            ->where('status', 'open')
            ->where(fn ($query) => $query
                ->where('order_id', $order->id)
                ->orWhereNull('order_id'))
            ->update([
                'status' => 'closed',
                'closed_at' => now(),
                'updated_at' => now(),
            ]);

        if ($closed > 0) {
            DiningTable::whereKey($order->table_id)->update(['status' => 'cleaning']);
        }
    }

    private function reverseCustomerStatistics(Order $order): void
    {
        $customer = Customer::lockForUpdate()->find($order->customer_id);
        if (! $customer) {
            return;
        }

        $customer->total_spent = max(
            (float) $customer->total_spent - (float) $order->total,
            0,
        );
        $customer->visit_count = max((int) $customer->visit_count - 1, 0);
        $customer->save();
    }
}
