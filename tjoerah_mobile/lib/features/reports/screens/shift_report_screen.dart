import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../settings/providers/printer_provider.dart';
import '../models/report_models.dart';
import '../providers/reports_provider.dart';

class ShiftReportScreen extends ConsumerStatefulWidget {
  const ShiftReportScreen({super.key});

  @override
  ConsumerState<ShiftReportScreen> createState() => _ShiftReportScreenState();
}

class _ShiftReportScreenState extends ConsumerState<ShiftReportScreen> {
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportsProvider).shiftReport;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan shift'),
        actions: [
          IconButton(
            tooltip: 'Hitung ulang laporan',
            onPressed: () => ref
                .read(reportsProvider.notifier)
                .generateShiftReport(DateTime.now()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: report == null
          ? const AppLoadingState(message: 'Menghitung transaksi shift...')
          : _buildReport(report),
    );
  }

  Widget _buildReport(ShiftReportModel report) {
    final currency = _currency();
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: AppSpacing.page(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ringkasan hari ini',
                                  style: theme.textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Berdasarkan transaksi yang tersimpan di perangkat ini.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          AppBadge(
                            text: AppDateFormatter.shortDate(report.date),
                            icon: Icons.calendar_today_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          return Row(
                            children: [
                              SizedBox(
                                width: width,
                                height: 116,
                                child: AppMetricCard(
                                  title: 'Total transaksi',
                                  value: '${report.totalOrders}',
                                  icon: Icons.receipt_long_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: width,
                                height: 116,
                                child: AppMetricCard(
                                  title: 'Pendapatan kotor',
                                  value: currency.format(report.totalRevenue),
                                  icon: Icons.payments_outlined,
                                  iconColor: AppColors.success,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rincian pembayaran',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Rekonsiliasi per metode',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Divider(color: theme.colorScheme.outline),
                            if (report.paymentBreakdown.isEmpty)
                              const SizedBox(
                                height: 180,
                                child: AppEmptyState(
                                  title: 'Belum ada pembayaran',
                                  message: 'Transaksi shift ini masih kosong.',
                                  icon: Icons.account_balance_wallet_outlined,
                                ),
                              )
                            else
                              ...report.paymentBreakdown.entries.map(
                                (entry) => ListTile(
                                  minTileHeight: 62,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  leading: Icon(_paymentIcon(entry.key)),
                                  title: Text(_paymentLabel(entry.key)),
                                  trailing: Text(
                                    currency.format(entry.value),
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outline)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AppButton(
                      text: 'Cetak laporan shift',
                      icon: Icons.print_outlined,
                      isLoading: _printing,
                      onPressed: () => _printReport(report),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(ShiftReportModel report) async {
    setState(() => _printing = true);
    try {
      final result = await ref.read(printerProvider.notifier).printShiftReport({
        'date': AppDateFormatter.shortDate(report.date),
        'total_orders': report.totalOrders,
        'total_revenue': report.totalRevenue,
        'payment_breakdown': report.paymentBreakdown,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Printer belum siap: $error')));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
}

String _paymentLabel(String method) => switch (method.toLowerCase()) {
  'cash' => 'Tunai',
  'qris' => 'QRIS',
  'card' => 'Kartu',
  'split' => 'Pembayaran terbagi',
  _ => method,
};

IconData _paymentIcon(String method) => switch (method.toLowerCase()) {
  'cash' => Icons.payments_outlined,
  'qris' => Icons.qr_code_2_rounded,
  'card' => Icons.credit_card_outlined,
  _ => Icons.account_balance_wallet_outlined,
};

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
