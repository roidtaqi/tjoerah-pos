<?php

namespace App\Domains\Reporting\Controllers;

use App\Domains\Inventory\Models\InventoryItem;
use App\Domains\Inventory\Models\StockMovement;
use App\Domains\POS\Models\Order;
use App\Domains\Reporting\Models\ProfitabilitySnapshot;
use App\Domains\Reporting\Models\SystemAlert;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ReportingController extends Controller
{
    public function sales(Request $request)
    {
        $refunds = $this->refundAmountSql();

        return response()->json($this->baseOrderQuery($request)
            ->selectRaw("DATE(orders.created_at) as date, COUNT(*) as orders, SUM(orders.total - {$refunds}) as total_sales, SUM({$refunds}) as refunds, SUM(orders.cogs_total) as cogs, SUM((orders.subtotal - orders.discount_total - {$refunds}) - orders.cogs_total) as gross_profit")
            ->groupBy(DB::raw('DATE(orders.created_at)'))
            ->orderBy('date')
            ->get());
    }

    public function exportSales(Request $request)
    {
        $refunds = $this->refundAmountSql();

        $data = $this->baseOrderQuery($request)
            ->selectRaw("DATE(orders.created_at) as date, COUNT(*) as orders, SUM(orders.total - {$refunds}) as total_sales, SUM({$refunds}) as refunds, SUM(orders.cogs_total) as cogs, SUM((orders.subtotal - orders.discount_total - {$refunds}) - orders.cogs_total) as gross_profit")
            ->groupBy(DB::raw('DATE(orders.created_at)'))
            ->orderByDesc('date')
            ->get();

        $csv = "Tanggal,Total Pesanan,Total Penjualan,Pengembalian,HPP (COGS),Laba Kotor\n";
        foreach ($data as $row) {
            $csv .= "{$row->date},{$row->orders},{$row->total_sales},{$row->refunds},{$row->cogs},{$row->gross_profit}\n";
        }

        return response($csv)
            ->header('Content-Type', 'text/csv')
            ->header('Content-Disposition', 'attachment; filename="laporan_penjualan.csv"');
    }

    public function products(Request $request)
    {
        $refunds = '(SELECT COALESCE(SUM(product_refunds.amount), 0) FROM refunds AS product_refunds WHERE product_refunds.order_item_id = order_items.id AND product_refunds.status = \'approved\' AND product_refunds.deleted_at IS NULL)';

        return DB::table('order_items')
            ->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->selectRaw("order_items.product_id, order_items.snapshot_name, SUM(order_items.qty) as qty, SUM(order_items.total - {$refunds}) as revenue, SUM({$refunds}) as refunds, SUM(order_items.cogs_total) as cogs")
            ->whereIn('orders.status', ['paid', 'completed', 'partially_refunded', 'refunded'])
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('orders.outlet_id', $outletId))
            ->when($request->date('from'), fn ($query, $from) => $query->whereDate('orders.created_at', '>=', $from))
            ->when($request->date('to'), fn ($query, $to) => $query->whereDate('orders.created_at', '<=', $to))
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
        $refunds = $this->refundAmountSql();

        return $this->baseOrderQuery($request)
            ->selectRaw("orders.outlet_id, COUNT(*) as orders, SUM(orders.total - {$refunds}) as revenue, SUM({$refunds}) as refunds, SUM(orders.cogs_total) as cogs, SUM((orders.subtotal - orders.discount_total - {$refunds}) - orders.cogs_total) as gross_profit")
            ->groupBy('orders.outlet_id')
            ->orderByDesc('revenue')
            ->get();
    }

    public function alerts(Request $request)
    {
        return response()->json(
            SystemAlert::whereNull('resolved_at')
                ->latest()
                ->get()
        );
    }

    private function baseOrderQuery(Request $request)
    {
        return Order::query()
            ->where(function ($query) {
                $query->whereIn('status', ['paid', 'completed', 'partially_refunded', 'refunded'])
                    ->orWhere(fn ($voided) => $voided
                        ->where('status', 'voided')
                        ->whereHas('payments', fn ($payments) => $payments->where('status', 'completed')));
            })
            ->when($request->integer('outlet_id'), fn ($query, $outletId) => $query->where('outlet_id', $outletId))
            ->when($request->date('from'), fn ($query, $from) => $query->whereDate('created_at', '>=', $from))
            ->when($request->date('to'), fn ($query, $to) => $query->whereDate('created_at', '<=', $to));
    }

    private function refundAmountSql(): string
    {
        return "(SELECT COALESCE(SUM(order_refunds.amount), 0) FROM refunds AS order_refunds WHERE order_refunds.order_id = orders.id AND order_refunds.status = 'approved' AND order_refunds.deleted_at IS NULL)";
    }
}
