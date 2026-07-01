<?php

namespace App\Domains\POS\Controllers;

use App\Http\Controllers\Controller;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\Payment;
use Illuminate\Http\Request;

class PaymentController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate([
            'order_id' => 'required|integer|exists:orders,id',
            'method' => 'required|string|max:100',
            'amount' => 'required|numeric|min:0',
            'reference_number' => 'nullable|string|max:255',
            'meta' => 'nullable|array',
        ]);

        $payment = Payment::create([
            ...$validated,
            'status' => 'completed',
            'paid_at' => now(),
        ]);

        $order = Order::find($validated['order_id']);
        if ($order && $order->payments()->sum('amount') >= $order->total) {
            $order->update(['status' => 'paid', 'completed_at' => $order->completed_at ?? now()]);
        }

        return response()->json($payment, 201);
    }
}
