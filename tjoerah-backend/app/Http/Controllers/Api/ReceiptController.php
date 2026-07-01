<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Order;

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
