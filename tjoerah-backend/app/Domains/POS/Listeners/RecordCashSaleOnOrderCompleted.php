<?php

namespace App\Domains\POS\Listeners;

use App\Domains\POS\Services\CashLedgerService;
use App\Domains\Sales\Events\OrderCompleted;
use Illuminate\Support\Facades\Log;
use Throwable;

class RecordCashSaleOnOrderCompleted
{
    public function __construct(private CashLedgerService $cashLedger) {}

    public function handle(OrderCompleted $event): void
    {
        try {
            $this->cashLedger->recordPaidOrder($event->order);
        } catch (Throwable $exception) {
            Log::error('Paid order could not be recorded in the cash ledger.', [
                'order_id' => $event->order->id,
                'error' => $exception->getMessage(),
            ]);
        }
    }
}
