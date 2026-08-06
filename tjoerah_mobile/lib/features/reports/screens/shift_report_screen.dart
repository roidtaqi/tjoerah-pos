import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cash/models/cash_model.dart';
import '../../cash/providers/cash_provider.dart';
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
    final cashOverview = ref.watch(cashProvider).value;
    final cashShift = report == null
        ? null
        : _cashShiftForDate(cashOverview, report.date);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan shift'),
        actions: [
          IconButton(
            tooltip: 'Hitung ulang laporan',
            onPressed: _refreshReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: report == null
          ? const AppLoadingState(message: 'Menghitung transaksi shift...')
          : _buildReport(report, cashShift),
    );
  }

  Widget _buildReport(ShiftReportModel report, CashShift? cashShift) {
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
                                  'Berdasarkan seluruh pembayaran pada outlet ini.',
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
                          final columns = constraints.maxWidth >= 760 ? 4 : 2;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 12) /
                              columns;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final metric in [
                                (
                                  'Total transaksi',
                                  '${report.totalOrders}',
                                  Icons.receipt_long_outlined,
                                  AppColors.info,
                                ),
                                (
                                  'Penjualan kotor',
                                  currency.format(report.grossRevenue),
                                  Icons.trending_up_rounded,
                                  AppColors.success,
                                ),
                                (
                                  'Refund',
                                  currency.format(report.refundTotal),
                                  Icons.keyboard_return_rounded,
                                  AppColors.error,
                                ),
                                (
                                  'Penjualan bersih',
                                  currency.format(report.totalRevenue),
                                  Icons.payments_outlined,
                                  AppColors.primary,
                                ),
                              ])
                                SizedBox(
                                  width: width,
                                  height: 116,
                                  child: AppMetricCard(
                                    title: metric.$1,
                                    value: metric.$2,
                                    icon: metric.$3,
                                    iconColor: metric.$4,
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
                                    'Metode pembayaran hari ini',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Seluruh perangkat pada outlet ini',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Divider(color: theme.colorScheme.outline),
                            ...report.paymentBreakdown.entries.map(
                              (entry) => ListTile(
                                minTileHeight: 62,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                leading: Icon(_paymentIcon(entry.key)),
                                title: Text(_paymentLabel(entry.key)),
                                subtitle: Text(
                                  '${report.paymentCounts[entry.key] ?? 0} transaksi',
                                ),
                                trailing: Text(
                                  currency.format(entry.value),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (cashShift != null) ...[
                        const SizedBox(height: 16),
                        _CashReconciliationCard(
                          shift: cashShift,
                          currency: currency,
                        ),
                      ],
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
                      onPressed: () => _printReport(report, cashShift),
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

  Future<void> _refreshReport() async {
    await Future.wait([
      ref.read(reportsProvider.notifier).generateShiftReport(DateTime.now()),
      ref.read(cashProvider.notifier).refresh(),
    ]);
  }

  Future<void> _printReport(
    ShiftReportModel report,
    CashShift? cashShift,
  ) async {
    setState(() => _printing = true);
    try {
      final user = ref.read(authProvider).user;
      final result = await ref.read(printerProvider.notifier).printShiftReport({
        'date': AppDateFormatter.shortDate(report.date),
        'generated_at': AppDateFormatter.longDateTime(DateTime.now()),
        'operator': user?['name']?.toString() ?? '-',
        'total_orders': report.totalOrders,
        'gross_revenue': report.grossRevenue,
        'refund_total': report.refundTotal,
        'total_revenue': report.totalRevenue,
        'payment_breakdown': report.paymentBreakdown,
        'payment_counts': report.paymentCounts,
        'refund_breakdown': report.refundBreakdown,
        if (cashShift != null)
          'cash_shift': {
            'number': cashShift.number,
            'opened_by': cashShift.openedBy,
            'started_at': AppDateFormatter.longDateTime(cashShift.startedAt),
            'ended_at': cashShift.endedAt == null
                ? null
                : AppDateFormatter.longDateTime(cashShift.endedAt!),
            'status': cashShift.status,
            'opening_cash': cashShift.summary.openingCash,
            'cash_sales': cashShift.summary.cashSales,
            'manual_cash_in': cashShift.summary.manualCashIn,
            'cash_refunds': cashShift.summary.cashRefunds,
            'manual_cash_out': cashShift.summary.manualCashOut,
            'adjustments_in': cashShift.summary.adjustmentsIn,
            'adjustments_out': cashShift.summary.adjustmentsOut,
            'cash_fund_balance': cashShift.summary.cashFundBalance,
            'cash_on_hand': cashShift.summary.cashOnHand,
            'expected_cash': cashShift.summary.expectedCash,
            'closing_cash': cashShift.summary.closingCash,
            'difference': cashShift.summary.difference,
          },
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

class _CashReconciliationCard extends StatelessWidget {
  const _CashReconciliationCard({required this.shift, required this.currency});

  final CashShift shift;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = shift.summary;
    return AppCard(
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
                  'Rincian tunai di kasir',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${shift.number} • ${shift.isOpen ? 'Masih berjalan' : 'Sudah ditutup'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Divider(color: theme.colorScheme.outline),
          _ReportLine(
            label: 'Saldo awal Uang Kas',
            value: currency.format(summary.openingCash),
          ),
          _ReportLine(
            label: 'Uang Kas masuk',
            value: currency.format(summary.cashFundIn),
          ),
          _ReportLine(
            label: 'Uang Kas keluar',
            value: currency.format(summary.cashFundOut),
          ),
          _ReportLine(
            label: 'Saldo Uang Kas',
            value: currency.format(summary.cashFundBalance),
            emphasized: true,
          ),
          _ReportLine(
            label: 'Penjualan tunai',
            value: currency.format(summary.cashSales),
          ),
          _ReportLine(
            label: 'Refund tunai',
            value: currency.format(summary.cashRefunds),
          ),
          _ReportLine(
            label: 'Total tunai di kasir',
            value: currency.format(summary.cashOnHand),
            emphasized: true,
          ),
          if (summary.closingCash != null)
            _ReportLine(
              label: 'Uang fisik',
              value: currency.format(summary.closingCash),
            ),
          if (summary.difference != null)
            _ReportLine(
              label: 'Selisih',
              value: currency.format(summary.difference),
              emphasized: true,
              valueColor: summary.difference == 0
                  ? AppColors.success
                  : AppColors.error,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

CashShift? _cashShiftForDate(CashOverview? overview, DateTime date) {
  if (overview == null) return null;
  final candidates = [
    if (overview.currentShift != null) overview.currentShift!,
    ...overview.recentShifts,
  ];
  for (final shift in candidates) {
    if (DateUtils.isSameDay(shift.startedAt.toLocal(), date)) return shift;
  }
  return null;
}

String _paymentLabel(String method) => switch (method.toLowerCase()) {
  'cash' => 'Tunai',
  'qris' => 'QRIS',
  'card' || 'debit_card' || 'debit' => 'Kartu debit',
  'split' => 'Pembayaran terbagi',
  _ => method,
};

IconData _paymentIcon(String method) => switch (method.toLowerCase()) {
  'cash' => Icons.payments_outlined,
  'qris' => Icons.qr_code_2_rounded,
  'card' || 'debit_card' || 'debit' => Icons.credit_card_outlined,
  _ => Icons.account_balance_wallet_outlined,
};

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
