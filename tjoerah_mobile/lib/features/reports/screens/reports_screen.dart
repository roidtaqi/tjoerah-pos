import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../models/report_models.dart';
import '../providers/reports_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          IconButton(
            tooltip: 'Laporan shift',
            onPressed: () => context.push('/shift-report'),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: 'Muat ulang laporan',
            onPressed: () => ref.read(reportsProvider.notifier).loadData(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ReportsState state) {
    final hasData = state.salesReport.isNotEmpty || state.margins.isNotEmpty;
    if (state.isLoading && !hasData) {
      return const AppLoadingState(message: 'Menyusun laporan outlet...');
    }
    if (state.error != null && !hasData) {
      return AppErrorState(
        message:
            'Laporan online belum tersedia. Laporan shift lokal tetap dapat dibuka.',
        onRetry: () => ref.read(reportsProvider.notifier).loadData(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(reportsProvider.notifier).loadData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReportToolbar(
              state: state,
              onDateTap: () => _selectDateRange(context, ref, state),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              const _OfflineReportBanner(),
            ],
            if (state.alerts.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AlertStrip(alerts: state.alerts),
            ],
            const SizedBox(height: 16),
            _MetricGrid(state: state),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final chart = _SalesChart(data: state.salesReport);
                final products = _ProductPerformance(products: state.margins);
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: chart),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: products),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [chart, const SizedBox(height: 16), products],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateRange(
    BuildContext context,
    WidgetRef ref,
    ReportsState state,
  ) async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: state.startDate,
        end: state.endDate,
      ),
      helpText: 'PILIH PERIODE LAPORAN',
      cancelText: 'BATAL',
      confirmText: 'TERAPKAN',
      saveText: 'TERAPKAN',
    );
    if (selected != null) {
      ref
          .read(reportsProvider.notifier)
          .setDateRange(selected.start, selected.end);
    }
  }
}

class _ReportToolbar extends StatelessWidget {
  const _ReportToolbar({required this.state, required this.onDateTap});

  final ReportsState state;
  final VoidCallback onDateTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kinerja outlet', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 3),
        Text(
          'Penjualan, biaya, dan margin dalam satu tampilan.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    final dateButton = OutlinedButton.icon(
      onPressed: onDateTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        '${AppDateFormatter.shortDate(state.startDate)} - '
        '${AppDateFormatter.shortDate(state.endDate)}',
        overflow: TextOverflow.ellipsis,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 12), dateButton],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 12),
            dateButton,
          ],
        );
      },
    );
  }
}

class _OfflineReportBanner extends StatelessWidget {
  const _OfflineReportBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Menampilkan data terakhir. Tarik ke bawah untuk mencoba sinkronisasi.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.alerts});

  final List<SystemAlertModel> alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = alerts.take(3).toList();
    return AppCard(
      borderColor: AppColors.warning.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Perlu perhatian',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              AppBadge(
                text: '${alerts.length}',
                color: AppColors.warning.withValues(alpha: 0.12),
                textColor: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...visible.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${alert.title}: ${alert.message}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    final currency = _currency();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              height: 120,
              child: AppMetricCard(
                title: 'Penjualan kotor',
                value: currency.format(state.totalRevenue),
                icon: Icons.payments_outlined,
                iconColor: AppColors.info,
              ),
            ),
            SizedBox(
              width: width,
              height: 120,
              child: AppMetricCard(
                title: 'Total HPP',
                value: currency.format(state.totalCOGS),
                icon: Icons.shopping_bag_outlined,
                iconColor: AppColors.warning,
              ),
            ),
            SizedBox(
              width: width,
              height: 120,
              child: AppMetricCard(
                title: 'Laba kotor',
                value: currency.format(state.totalGrossProfit),
                icon: Icons.trending_up_rounded,
                iconColor: AppColors.success,
              ),
            ),
            SizedBox(
              width: width,
              height: 120,
              child: AppMetricCard(
                title: 'Margin kotor',
                value: '${state.grossMarginPercent.toStringAsFixed(1)}%',
                icon: Icons.donut_large_outlined,
                iconColor: AppColors.accent,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.data});

  final List<SalesReportModel> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 14),
      child: SizedBox(
        height: 330,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tren penjualan', style: theme.textTheme.titleMedium),
            const SizedBox(height: 3),
            Text('Pendapatan per hari', style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            Expanded(
              child: data.isEmpty
                  ? const AppEmptyState(
                      title: 'Belum ada penjualan',
                      message: 'Data akan muncul setelah transaksi tersinkron.',
                      icon: Icons.show_chart_rounded,
                    )
                  : _buildChart(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final theme = Theme.of(context);
    final maxSales = data.fold<double>(
      0,
      (maxValue, item) => math.max(maxValue, item.totalSales),
    );
    final maxY = maxSales <= 0 ? 1.0 : maxSales * 1.18;
    final spots = data
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.totalSales))
        .toList();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: math.max(1, (data.length / 4).ceil()).toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final date = DateTime.tryParse(data[index].date);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    date == null
                        ? data[index].date
                        : AppDateFormatter.dayMonth(date),
                    style: theme.textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    _currency().format(spot.y),
                    TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: spots.length > 2,
            color: theme.colorScheme.secondary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: spots.length <= 7),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.secondary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPerformance extends StatelessWidget {
  const _ProductPerformance({required this.products});

  final List<ProductMarginModel> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = products.take(8).toList();
    return AppCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 366,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kinerja produk', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    'Produk terlaris dan margin kotor',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Divider(color: theme.colorScheme.outline),
            Expanded(
              child: visible.isEmpty
                  ? const AppEmptyState(
                      title: 'Belum ada data produk',
                      message: 'Produk terjual akan muncul di sini.',
                      icon: Icons.local_cafe_outlined,
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final product = visible[index];
                        final lowMargin = product.marginPercent < 60;
                        return ListTile(
                          minTileHeight: 62,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: SizedBox(
                            width: 28,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            '${product.qty} terjual - ${_currency().format(product.revenue)}',
                          ),
                          trailing: AppBadge(
                            text:
                                '${product.marginPercent.toStringAsFixed(1)}%',
                            color:
                                (lowMargin
                                        ? AppColors.warning
                                        : AppColors.success)
                                    .withValues(alpha: 0.12),
                            textColor: lowMargin
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
