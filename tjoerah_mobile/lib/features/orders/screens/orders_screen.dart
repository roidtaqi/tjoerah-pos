import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
import '../models/order_history_model.dart';
import '../providers/order_history_provider.dart';

enum _OrderFilter { all, synced, pending }

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _query = '';
  _OrderFilter _filter = _OrderFilter.all;

  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(orderHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(orderHistoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: orders.when(
        loading: () => const AppLoadingState(message: 'Memuat pesanan...'),
        error: (error, _) => AppErrorState(
          message: 'Riwayat lokal belum dapat dibaca.',
          onRetry: () => ref.read(orderHistoryProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<OrderHistoryItem> orders) {
    final today = DateTime.now();
    final todayOrders = orders.where(
      (order) =>
          order.createdAt.year == today.year &&
          order.createdAt.month == today.month &&
          order.createdAt.day == today.day,
    );
    final pending = orders.where((order) => order.isPending).length;
    final revenue = todayOrders.fold<double>(
      0,
      (sum, order) => sum + order.total,
    );
    final normalized = _query.trim().toLowerCase();
    final filtered = orders.where((order) {
      final matchesFilter = switch (_filter) {
        _OrderFilter.all => true,
        _OrderFilter.synced => !order.isPending,
        _OrderFilter.pending => order.isPending,
      };
      final matchesQuery =
          normalized.isEmpty ||
          order.receiptNumber.toLowerCase().contains(normalized) ||
          (order.customerName?.toLowerCase().contains(normalized) ?? false) ||
          order.items.any(
            (item) => item.name.toLowerCase().contains(normalized),
          );
      return matchesFilter && matchesQuery;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(orderHistoryProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page(context),
        children: [
          _Metrics(
            orderCount: todayOrders.length,
            revenue: _currency.format(revenue),
            pendingCount: pending,
          ),
          const SizedBox(height: 20),
          AppSearchBar(
            hintText: 'Cari nomor struk, produk, atau pelanggan',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_OrderFilter>(
              segments: [
                const ButtonSegment(
                  value: _OrderFilter.all,
                  label: Text('Semua'),
                ),
                const ButtonSegment(
                  value: _OrderFilter.synced,
                  label: Text('Tersimpan'),
                ),
                ButtonSegment(
                  value: _OrderFilter.pending,
                  label: Text('Antrean ($pending)'),
                ),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _filter = selection.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            AppEmptyState(
              title: orders.isEmpty
                  ? 'Belum ada pesanan'
                  : 'Pesanan tidak ditemukan',
              message: orders.isEmpty
                  ? 'Transaksi yang selesai akan muncul di sini.'
                  : 'Ubah kata pencarian atau status pesanan.',
              icon: Icons.receipt_long_outlined,
            )
          else
            ...filtered.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderRow(
                  order: order,
                  date: AppDateFormatter.dayMonthTime(order.createdAt),
                  total: _currency.format(order.total),
                  onTap: () => _showDetail(order),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDetail(OrderHistoryItem order) {
    AppBottomSheet.show<void>(
      context,
      title: order.receiptNumber,
      subtitle: AppDateFormatter.dayMonthTime(order.createdAt),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppBadge(
                  text: _orderTypeLabel(order.orderType),
                  icon: Icons.restaurant_outlined,
                ),
                AppBadge(
                  text: order.isPending ? 'Belum sinkron' : 'Tersimpan',
                  color: order.isPending
                      ? AppColors.warningSoft
                      : AppColors.successSoft,
                  textColor: order.isPending
                      ? AppColors.warning
                      : AppColors.success,
                  icon: order.isPending
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_done_outlined,
                ),
              ],
            ),
            if (order.customerName != null) ...[
              const SizedBox(height: 18),
              _DetailLine(label: 'Pelanggan', value: order.customerName!),
            ],
            const SizedBox(height: 18),
            Text(
              'Rincian item',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 32, child: Text('${item.quantity}x')),
                    Expanded(child: Text(item.name)),
                    const SizedBox(width: 12),
                    Text(_currency.format(item.total)),
                  ],
                ),
              ),
            ),
            const Divider(height: 28),
            _DetailLine(
              label: 'Pembayaran',
              value: _paymentLabel(order.paymentMethod),
            ),
            const SizedBox(height: 10),
            _DetailLine(
              label: 'Total',
              value: _currency.format(order.total),
              emphasized: true,
            ),
            if (order.note != null && order.note!.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Catatan', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(order.note!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.orderCount,
    required this.revenue,
    required this.pendingCount,
  });

  final int orderCount;
  final String revenue;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: 'Pesanan hari ini',
                value: '$orderCount',
                icon: Icons.receipt_long_outlined,
                iconColor: AppColors.info,
              ),
            ),
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: 'Penjualan hari ini',
                value: revenue,
                icon: Icons.payments_outlined,
                iconColor: AppColors.success,
              ),
            ),
            if (columns == 3)
              SizedBox(
                width: width,
                height: 112,
                child: AppMetricCard(
                  title: 'Antrean sinkron',
                  value: '$pendingCount',
                  icon: Icons.cloud_upload_outlined,
                  iconColor: pendingCount == 0
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.date,
    required this.total,
    required this.onTap,
  });

  final OrderHistoryItem order;
  final String date;
  final String total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_outlined, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.receiptNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(total, style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_orderTypeLabel(order.orderType)} · ${order.itemCount} item · $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (order.isPending) ...[
                  const SizedBox(height: 7),
                  const AppBadge(
                    text: 'Menunggu sinkron',
                    color: AppColors.warningSoft,
                    textColor: AppColors.warning,
                    icon: Icons.cloud_upload_outlined,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, style: style),
      ],
    );
  }
}

String _orderTypeLabel(String value) => switch (value) {
  'dine_in' => 'Makan di tempat',
  'delivery' => 'Pesan antar',
  _ => 'Bawa pulang',
};

String _paymentLabel(String value) => switch (value) {
  'cash' => 'Tunai',
  'qris' => 'QRIS',
  'debit' => 'Kartu debit',
  'credit_card' => 'Kartu kredit',
  'ewallet' => 'Dompet digital',
  'split' => 'Pembayaran terpisah',
  _ => value.toUpperCase(),
};
