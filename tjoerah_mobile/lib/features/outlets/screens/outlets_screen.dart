import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
import '../models/outlet_summary_model.dart';
import '../providers/outlet_provider.dart';

class OutletsScreen extends ConsumerStatefulWidget {
  const OutletsScreen({super.key});

  @override
  ConsumerState<OutletsScreen> createState() => _OutletsScreenState();
}

class _OutletsScreenState extends ConsumerState<OutletsScreen> {
  String _query = '';
  bool _attentionOnly = false;
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final outlets = ref.watch(outletProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pemantauan outlet'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(outletProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: outlets.when(
        loading: () => const AppLoadingState(message: 'Memuat outlet...'),
        error: (error, _) => AppErrorState(
          message: 'Data outlet belum tersedia secara offline.',
          onRetry: () => ref.read(outletProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<OutletSummaryModel> outlets) {
    final query = _query.trim().toLowerCase();
    final filtered = outlets.where((outlet) {
      final matchesQuery =
          query.isEmpty ||
          outlet.name.toLowerCase().contains(query) ||
          (outlet.address?.toLowerCase().contains(query) ?? false);
      return matchesQuery && (!_attentionOnly || outlet.needsAttention);
    }).toList();
    final active = outlets.where((outlet) => outlet.isActive).length;
    final attention = outlets.where((outlet) => outlet.needsAttention).length;
    final revenue = outlets.fold<double>(
      0,
      (sum, outlet) => sum + outlet.revenue,
    );

    return RefreshIndicator(
      onRefresh: () => ref.read(outletProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page(context),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    height: 112,
                    child: AppMetricCard(
                      title: 'Outlet aktif',
                      value: '$active',
                      icon: Icons.store_outlined,
                      iconColor: AppColors.info,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    height: 112,
                    child: AppMetricCard(
                      title: 'Perlu perhatian',
                      value: '$attention',
                      icon: Icons.warning_amber_rounded,
                      iconColor: attention == 0
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                  if (columns == 3)
                    SizedBox(
                      width: width,
                      height: 112,
                      child: AppMetricCard(
                        title: 'Total penjualan',
                        value: _currency.format(revenue),
                        icon: Icons.payments_outlined,
                        iconColor: AppColors.success,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          AppSearchBar(
            hintText: 'Cari outlet atau alamat',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          FilterChip(
            selected: _attentionOnly,
            avatar: const Icon(Icons.warning_amber_rounded, size: 18),
            label: Text('Perlu perhatian ($attention)'),
            onSelected: (value) => setState(() => _attentionOnly = value),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            AppEmptyState(
              title: outlets.isEmpty
                  ? 'Belum ada outlet'
                  : 'Outlet tidak ditemukan',
              message: outlets.isEmpty
                  ? 'Outlet yang ditugaskan akan muncul di sini.'
                  : 'Ubah pencarian atau matikan filter perhatian.',
              icon: Icons.store_outlined,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1050
                    ? 3
                    : constraints.maxWidth >= 680
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: filtered
                      .map(
                        (outlet) => SizedBox(
                          width: width,
                          child: _OutletCard(
                            outlet: outlet,
                            revenue: _currency.format(outlet.revenue),
                            onTap: () => _showOutlet(outlet),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showOutlet(OutletSummaryModel outlet) {
    AppBottomSheet.show<void>(
      context,
      title: outlet.name,
      subtitle: outlet.address ?? 'Alamat belum diisi',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBadge(
                text: outlet.isActive ? 'Aktif' : 'Nonaktif',
                color: outlet.isActive
                    ? AppColors.successSoft
                    : AppColors.errorSoft,
                textColor: outlet.isActive
                    ? AppColors.success
                    : AppColors.error,
              ),
            ),
            const SizedBox(height: 18),
            _OutletDetail(label: 'Pesanan', value: '${outlet.orders}'),
            const SizedBox(height: 12),
            _OutletDetail(
              label: 'Penjualan',
              value: _currency.format(outlet.revenue),
            ),
            const SizedBox(height: 12),
            _OutletDetail(
              label: 'Laba kotor',
              value: _currency.format(outlet.grossProfit),
            ),
            const SizedBox(height: 12),
            _OutletDetail(
              label: 'Margin',
              value: '${outlet.marginPercent.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Buka laporan',
              icon: Icons.bar_chart_rounded,
              onPressed: () {
                Navigator.pop(context);
                context.go('/reports');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OutletCard extends StatelessWidget {
  const _OutletCard({
    required this.outlet,
    required this.revenue,
    required this.onTap,
  });

  final OutletSummaryModel outlet;
  final String revenue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.store_outlined, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  outlet.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                outlet.needsAttention
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                color: outlet.needsAttention
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Penjualan', style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(revenue, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('${outlet.orders} pesanan')),
              Text('${outlet.marginPercent.toStringAsFixed(1)}% margin'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutletDetail extends StatelessWidget {
  const _OutletDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
