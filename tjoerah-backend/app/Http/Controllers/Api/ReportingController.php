<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\InventoryItem;
use App\Models\Order;
use App\Models\ProfitabilitySnapshot;
use App\Models\StockMovement;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ReportingController extends Controller
{
    public function sales(Request $request)
    {
        return response()->json($this->baseOrderQuery($request)
            ->selectRaw('DATE(created_at) as date, COUNT(*) as orders, SUM(total) as total_sales, SUM(cogs_total) as cogs, SUM(gross_profit) as gross_profit')
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy('date')
            ->get());
    }

    public function products(Request $request)
    {
        return DB::table('order_items')
            ->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->selectRaw('order_items.product_id, order_items.snapshot_name, SUM(order_items.qty) as qty, SUM(order_items.total) as revenue')
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('orders.outlet_id', $outletId))
            ->groupBy('order_items.product_id', 'order_items.snapshot_name')
            ->orderByDesc('revenue')
            ->limit(50)
            ->get();
    }

    public function inventory(Request $request)
    {
        return response()->json([
            'item_count' => InventoryItem::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))->count(),
            'low_stock_items' => InventoryItem::whereColumn('minimum_stock', '>', 'weighted_average_cost')->limit(25)->get(),
            'recent_movements' => StockMovement::latest()->limit(25)->get(),
        ]);
    }

    public function profitability(Request $request)
    {
        return ProfitabilitySnapshot::when($request->integer('company_id'), fn ($query, $companyId) => $query->where('company_id', $companyId))
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->orderByDesc('period_date')
            ->paginate(100);
    }

    public function outlets(Request $request)
    {
        return $this->baseOrderQuery($request)
            ->selectRaw('outlet_id, COUNT(*) as orders, SUM(total) as revenue, SUM(cogs_total) as cogs, SUM(gross_profit) as gross_profit')
            ->groupBy('outlet_id')
            ->orderByDesc('revenue')
            ->get();
    }

    private function baseOrderQuery(Request $request)
    {
        return Order::query()
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($request->date('from'), fn ($query, $from) => $query->whereDate('created_at', '>=', $from))
            ->when($request->date('to'), fn ($query, $to) => $query->whereDate('created_at', '<=', $to));
    }
}
