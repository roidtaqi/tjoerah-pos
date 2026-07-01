<?php

namespace App\Domains\POS\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Domains\POS\Models\Order;
use App\Domains\POS\Models\OrderItem;
use App\Domains\POS\Models\Payment;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class SyncController extends Controller
{
    public function syncBatch(Request $request)
    {
        $batch = $request->input('batch', []);

        if (empty($batch)) {
            return response()->json(['message' => 'No items to sync'], 200);
        }

        DB::beginTransaction();

        try {
            foreach ($batch as $item) {
                $operation = $item['operation'];
                $entityType = $item['entity_type'];
                $payload = $item['payload'];

                if ($operation === 'CREATE' && $entityType === 'ORDER') {
                    // Create Order
                    $order = Order::firstOrCreate(
                        ['id' => $payload['id']],
                        [
                            'total' => $payload['total'],
                            'status' => $payload['status'],
                            'created_at' => $payload['created_at'],
                        ]
                    );

                    // Create Order Items
                    if (isset($payload['items']) && is_array($payload['items'])) {
                        foreach ($payload['items'] as $orderItem) {
                            OrderItem::firstOrCreate(
                                ['id' => $orderItem['id']],
                                [
                                    'order_id' => $payload['id'],
                                    'product_id' => $orderItem['product_id'],
                                    'quantity' => $orderItem['quantity'],
                                    'price' => $orderItem['price'],
                                ]
                            );
                        }
                    }

                    \App\Domains\Sales\Events\OrderCompleted::dispatch($order);
                }
                
                // Add more handlers for UPDATE, DELETE, and other entities (e.g. CUSTOMERS) as needed
            }

            DB::commit();
            return response()->json(['message' => 'Sync successful', 'synced_count' => count($batch)], 200);

        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Sync failed: ' . $e->getMessage());
            return response()->json(['message' => 'Sync failed', 'error' => $e->getMessage()], 500);
        }
    }
}
