import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/role_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../outlets/models/outlet_summary_model.dart';
import '../../outlets/providers/outlet_provider.dart';
import '../../reports/models/report_models.dart';
import '../../reports/providers/reports_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsProvider);
    final inventory = ref.watch(inventoryProvider).value;
    final outlets = ref.watch(outletProvider).value ?? [];
    final role = appRoleForUser(ref.watch(authProvider).user);
    final lowStock =
        inventory?.items.where((item) => item.isLowStock).toList() ?? [];
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final isAreaManager = role == AppRole.areaManager;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAreaManager ? 'Pemantauan area' : 'Dashboard bisnis'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () {
              ref.read(reportsProvider.notifier).loadData();
              ref.read(inventoryProvider.notifier).refresh();
              ref.read(outletProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(reportsProvider.notifier).loadData(),
            ref.read(inventoryProvider.notifier).refresh(),
            ref.read(outletProvider.notifier).refresh(),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.page(context),
          children: [
            Text(
              isAreaManager ? 'Kondisi outlet' : 'Kinerja perusahaan',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              AppDateFormatter.longDate(DateTime.now()),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (reports.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 20,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Menampilkan data terakhir yang tersedia.'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _DashboardMetrics(
              revenue: currency.format(reports.totalRevenue),
              grossProfit: currency.format(reports.totalGrossProfit),
              margin: '${reports.grossMarginPercent.toStringAsFixed(1)}%',
              alertCount: lowStock.length,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 820;
                final comparison = _OutletComparison(
                  outlets: outlets,
                  currency: currency,
                  onOpen: () => context.go('/outlets'),
                );
                final products = _TopProducts(
                  products: reports.margins,
                  currency: currency,
                  onOpen: () => context.go('/reports'),
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: comparison),
                      const SizedBox(width: 16),
                      Expanded(child: products),
                    ],
                  );
                }
                return Column(
                  children: [comparison, const SizedBox(height: 16), products],
                );
              },
            ),
            const SizedBox(height: 16),
            _StockAlerts(
              names: lowStock.map((item) => item.name).toList(),
              onOpen: () => context.go('/inventory'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({
    required this.revenue,
    required this.grossProfit,
    required this.margin,
    required this.alertCount,
  });

  final String revenue;
  final String grossProfit;
  final String margin;
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: 'Penjualan',
                value: revenue,
                icon: Icons.payments_outlined,
                iconColor: AppColors.info,
              ),
            ),
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: 'Laba kotor',
                value: grossProfit,
                icon: Icons.trending_up_rounded,
                iconColor: AppColors.success,
              ),
            ),
            if (columns == 4) ...[
              SizedBox(
                width: width,
                height: 112,
                child: AppMetricCard(
                  title: 'Margin kotor',
                  value: margin,
                  icon: Icons.percent_rounded,
                  iconColor: AppColors.success,
                ),
              ),
              SizedBox(
                width: width,
                height: 112,
                child: AppMetricCard(
                  title: 'Peringatan stok',
                  value: '$alertCount',
                  icon: Icons.warning_amber_rounded,
                  iconColor: alertCount == 0
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OutletComparison extends StatelessWidget {
  const _OutletComparison({
    required this.outlets,
    required this.currency,
    required this.onOpen,
  });

  final List<OutletSummaryModel> outlets;
  final NumberFormat currency;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sorted = [...outlets]..sort((a, b) => b.revenue.compareTo(a.revenue));
    final visible = sorted.take(4).toList();
    final maxRevenue = visible.isEmpty
        ? 1.0
        : visible
              .map((outlet) => outlet.revenue)
              .reduce((a, b) => a > b ? a : b)
              .clamp(1.0, double.infinity)
              .toDouble();

    return AppCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 294,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Perbandingan outlet',
              actionLabel: 'Lihat semua',
              onAction: onOpen,
            ),
            const Divider(),
            Expanded(
              child: visible.isEmpty
                  ? const _CompactEmpty(
                      title: 'Belum ada perbandingan',
                      message: 'Data outlet akan muncul setelah sinkron.',
                      icon: Icons.store_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final outlet = visible[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    outlet.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(currency.format(outlet.revenue)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 7,
                                value: outlet.revenue / maxRevenue,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                color: outlet.needsAttention
                                    ? AppColors.warning
                                    : AppColors.info,
                              ),
                            ),
                          ],
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

class _TopProducts extends StatelessWidget {
  const _TopProducts({
    required this.products,
    required this.currency,
    required this.onOpen,
  });

  final List<ProductMarginModel> products;
  final NumberFormat currency;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final visible = products.take(4).toList();
    return AppCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 294,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Produk teratas',
              actionLabel: 'Analisis',
              onAction: onOpen,
            ),
            const Divider(),
            Expanded(
              child: visible.isEmpty
                  ? const _CompactEmpty(
                      title: 'Belum ada penjualan',
                      message: 'Produk teratas akan muncul setelah transaksi.',
                      icon: Icons.local_cafe_outlined,
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final product = visible[index];
                        return ListTile(
                          minTileHeight: 54,
                          leading: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${product.qty} terjual'),
                          trailing: Text(currency.format(product.revenue)),
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

class _StockAlerts extends StatelessWidget {
  const _StockAlerts({required this.names, required this.onOpen});

  final List<String> names;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'Peringatan stok',
            actionLabel: 'Buka stok',
            onAction: onOpen,
          ),
          const Divider(),
          if (names.isEmpty)
            const SizedBox(
              height: 160,
              child: _CompactEmpty(
                title: 'Stok terkendali',
                message: 'Tidak ada item di bawah batas minimum.',
                icon: Icons.check_circle_outline_rounded,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: names
                    .take(8)
                    .map(
                      (name) => AppBadge(
                        text: name,
                        color: AppColors.warningSoft,
                        textColor: AppColors.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: theme.colorScheme.secondary),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
