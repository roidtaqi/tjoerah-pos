<?php

namespace App\Domains\POS\Controllers;

use App\Http\Controllers\Controller;
use App\Domains\POS\Models\Order;

class ReceiptController extends Controller
{
    public function show(Order $order)
    {
        return response()->json([
            'receipt_number' => $order->receipt_number,
            'order' => $order->load(['items', 'payments']),
            'digital_receipt_url' => url("/receipts/{$order->id}"),
        ]);
    }
}
