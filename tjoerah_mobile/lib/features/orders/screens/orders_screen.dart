import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/role_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cash/models/cash_model.dart';
import '../../cash/providers/cash_provider.dart';
import '../../customers/providers/customer_provider.dart';
import '../../kds/providers/kds_provider.dart';
import '../../pos/providers/table_provider.dart';
import '../../pos/providers/cart_provider.dart';
import '../../settings/providers/printer_provider.dart';
import '../models/order_history_model.dart';
import '../providers/order_history_provider.dart';

enum _OrderFilter { all, openBill, synced, pending }

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _query = '';
  _OrderFilter _filter = _OrderFilter.all;
  bool _isMutating = false;
  late DateTimeRange _dateRange;

  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _dateRange = DateTimeRange(start: today, end: today);
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(orderHistoryProvider);
    final cashOverview = ref.watch(cashProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isMutating ? null : _refreshOrders,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isMutating
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: orders.when(
        loading: () => const AppLoadingState(message: 'Memuat pesanan...'),
        error: (error, _) => AppErrorState(
          message: 'Riwayat lokal belum dapat dibaca.',
          onRetry: _refreshOrders,
        ),
        data: (items) => _buildContent(items, cashOverview),
      ),
    );
  }

  Widget _buildContent(
    List<OrderHistoryItem> orders,
    AsyncValue<CashOverview> cashOverview,
  ) {
    final today = DateTime.now();
    final periodOrders = orders.where(
      (order) => _isWithinDateRange(order.createdAt),
    );
    final pending = periodOrders.where((order) => order.isPending).length;
    final openBills = orders.where((order) => order.isOpenBill).length;
    final paidPeriod = periodOrders.where((order) => order.isPaid);
    final revenue = paidPeriod.fold<double>(
      0,
      (sum, order) => sum + order.total - order.refundedAmount,
    );
    final paymentSummaries = _summarizePayments(paidPeriod);
    final isToday =
        _isSingleDay(_dateRange) &&
        DateUtils.isSameDay(_dateRange.start, today);
    final normalized = _query.trim().toLowerCase();
    final filtered = orders.where((order) {
      final matchesFilter = switch (_filter) {
        _OrderFilter.all => true,
        _OrderFilter.openBill => order.isOpenBill,
        _OrderFilter.synced => !order.isPending,
        _OrderFilter.pending => order.isPending,
      };
      final matchesDate =
          _isWithinDateRange(order.createdAt) ||
          (order.isOpenBill &&
              const {
                _OrderFilter.all,
                _OrderFilter.openBill,
              }.contains(_filter));
      final matchesQuery =
          normalized.isEmpty ||
          order.receiptNumber.toLowerCase().contains(normalized) ||
          (order.customerName?.toLowerCase().contains(normalized) ?? false) ||
          order.items.any(
            (item) => item.name.toLowerCase().contains(normalized),
          );
      return matchesFilter && matchesDate && matchesQuery;
    }).toList();

    return RefreshIndicator(
      onRefresh: _refreshOrders,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page(context),
        children: [
          _DateRangeToolbar(
            label: _dateRangeLabel(_dateRange),
            isToday: isToday,
            onSelect: _selectDateRange,
            onToday: _showToday,
          ),
          const SizedBox(height: 12),
          _Metrics(
            orderCount: paidPeriod.length,
            revenue: _currency.format(revenue),
            pendingCount: pending,
            openBillCount: openBills,
            isToday: isToday,
          ),
          const SizedBox(height: 12),
          _PaymentSummaryTable(
            summaries: paymentSummaries,
            currency: _currency,
            isToday: isToday,
            cashOverview: cashOverview,
            onOpenCash: () => context.push('/cash'),
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
                  value: _OrderFilter.openBill,
                  label: Text('Open bill ($openBills)'),
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
                  : 'Ubah periode, kata pencarian, atau status pesanan.',
              icon: Icons.receipt_long_outlined,
            )
          else
            ...filtered.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderRow(
                  order: order,
                  date: AppDateFormatter.dayMonthTime(
                    order.createdAt.toLocal(),
                  ),
                  total: _currency.format(order.total),
                  onTap: () => _showDetail(order),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshOrders() async {
    await Future.wait([
      ref
          .read(orderHistoryProvider.notifier)
          .refresh(dateFrom: _dateRange.start, dateTo: _dateRange.end),
      ref.read(cashProvider.notifier).refresh(),
    ]);
  }

  Future<void> _selectDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      initialDateRange: _dateRange,
      helpText: 'PILIH PERIODE PESANAN',
      cancelText: 'BATAL',
      confirmText: 'TERAPKAN',
      saveText: 'TERAPKAN',
    );
    if (selected == null || !mounted) return;
    setState(() => _dateRange = selected);
    await _refreshOrders();
  }

  Future<void> _showToday() async {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() => _dateRange = DateTimeRange(start: today, end: today));
    await _refreshOrders();
  }

  bool _isWithinDateRange(DateTime value) {
    final date = DateUtils.dateOnly(value.toLocal());
    return !date.isBefore(_dateRange.start) && !date.isAfter(_dateRange.end);
  }

  void _showDetail(OrderHistoryItem order) {
    final canCancel =
        canCancelOrdersForUser(ref.read(authProvider).user) &&
        order.canBeCancelled &&
        !order.isPending &&
        order.serverId != null;
    final canRefund =
        canManageCatalogForUser(ref.read(authProvider).user) &&
        order.isPaid &&
        !order.isPending &&
        order.serverId != null &&
        order.items.any((item) => item.id != null) &&
        order.refundedAmount < order.total;
    AppBottomSheet.show<void>(
      context,
      title: order.receiptNumber,
      subtitle: AppDateFormatter.dayMonthTime(order.createdAt.toLocal()),
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
                if (order.isRefunded)
                  const AppBadge(
                    text: 'Refund',
                    color: AppColors.errorSoft,
                    textColor: AppColors.error,
                    icon: Icons.currency_exchange_rounded,
                  ),
                if (order.isOpenBill)
                  const AppBadge(
                    text: 'Open bill',
                    color: AppColors.infoSoft,
                    textColor: AppColors.info,
                    icon: Icons.bookmark_added_outlined,
                  ),
                if (order.isVoided)
                  const AppBadge(
                    text: 'Dibatalkan',
                    color: AppColors.errorSoft,
                    textColor: AppColors.error,
                    icon: Icons.cancel_outlined,
                  ),
                if (!order.isOpenBill)
                  AppBadge(
                    text: order.paymentSummary,
                    color: _paymentColor(order.paymentMethods.firstOrNull),
                    textColor: _paymentTextColor(
                      order.paymentMethods.firstOrNull,
                    ),
                    icon: _paymentIcon(order.paymentMethods.firstOrNull),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name),
                          if (order.isOpenBill) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Batch ${item.submissionBatch} · '
                              '${AppDateFormatter.dayMonthTime((item.submittedAt ?? order.createdAt).toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(_currency.format(item.total)),
                  ],
                ),
              ),
            ),
            const Divider(height: 28),
            _DetailLine(label: 'Pembayaran', value: order.paymentSummary),
            const SizedBox(height: 10),
            _DetailLine(
              label: 'Total',
              value: _currency.format(order.total),
              emphasized: true,
            ),
            if (order.refundedAmount > 0) ...[
              const SizedBox(height: 10),
              _DetailLine(
                label: 'Sudah direfund',
                value: _currency.format(order.refundedAmount),
              ),
              const SizedBox(height: 10),
              _DetailLine(
                label: 'Penjualan bersih',
                value: _currency.format(order.total - order.refundedAmount),
                emphasized: true,
              ),
            ],
            if (order.note != null && order.note!.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Catatan', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(order.note!),
            ],
            if (order.isVoided) ...[
              const SizedBox(height: 18),
              Text(
                'Pembatalan',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _DetailLine(
                label: 'Alasan',
                value: order.cancellationReason ?? '-',
              ),
              const SizedBox(height: 10),
              _DetailLine(
                label: 'Stok bahan',
                value: order.cancellationInventoryOutcome == 'restore_stock'
                    ? 'Dikembalikan'
                    : 'Tetap terpakai',
              ),
            ],
            if (order.isOpenBill) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: order.isPending || order.serverId == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        _returnOpenBillToCart(order);
                      },
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Tambah item ke open bill'),
              ),
              const SizedBox(height: 10),
              AppButton(
                text: order.isPending || order.serverId == null
                    ? 'Sinkronkan sebelum membayar'
                    : 'Bayar open bill',
                icon: Icons.payments_outlined,
                onPressed: order.isPending || order.serverId == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        Future<void>.delayed(
                          const Duration(milliseconds: 180),
                          () {
                            if (mounted) _openOpenBillPayment(order);
                          },
                        );
                      },
              ),
            ],
            const Divider(height: 28),
            Consumer(
              builder: (context, ref, _) {
                final printer = ref.watch(printerProvider);
                return _OrderPrintActions(
                  state: printer,
                  isOpenBill: order.isOpenBill,
                  isCancelled: order.isVoided,
                  onReceipt: () => _reprint(order, receiptOnly: true),
                  onKitchen: () => _reprint(order, kitchenOnly: true),
                  onAll: () => _reprint(order),
                );
              },
            ),
            if (canRefund) ...[
              const Divider(height: 28),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Future<void>.delayed(const Duration(milliseconds: 180), () {
                    if (mounted) _openRefund(order);
                  });
                },
                icon: const Icon(Icons.currency_exchange_rounded),
                label: const Text('Proses refund'),
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 12),
              AppButton(
                text: 'Batalkan pesanan',
                icon: Icons.cancel_outlined,
                variant: AppButtonVariant.danger,
                onPressed: () {
                  Navigator.pop(context);
                  Future<void>.delayed(const Duration(milliseconds: 180), () {
                    if (mounted) _openCancellation(order);
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openRefund(OrderHistoryItem order) async {
    final draft = await AppBottomSheet.show<_RefundDraft>(
      context,
      title: 'Refund pesanan',
      subtitle: order.receiptNumber,
      child: _RefundForm(order: order),
    );
    if (draft == null || !mounted) return;

    setState(() => _isMutating = true);
    final result = await ref
        .read(orderHistoryProvider.notifier)
        .refundOrder(
          order: order,
          item: draft.item,
          quantity: draft.quantity,
          amount: draft.amount,
          inventoryOutcome: draft.inventoryOutcome,
          reason: draft.reason,
        );
    if (!mounted) return;
    setState(() => _isMutating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
  }

  void _returnOpenBillToCart(OrderHistoryItem order) {
    final discountPercent = order.subtotal > 0
        ? (order.discount / order.subtotal * 100).clamp(0, 100).toDouble()
        : 0.0;
    ref
        .read(cartProvider.notifier)
        .startOpenBillEdit(
          serverId: order.serverId!,
          receiptNumber: order.receiptNumber,
          createdAt: order.createdAt,
          openBillLabel: order.openBillDisplayLabel,
          submittedItems: order.items
              .map(
                (item) => SubmittedCartItem(
                  productId: item.productId,
                  name: item.name,
                  price: item.price,
                  quantity: item.quantity,
                  station: item.station,
                  submissionBatch: item.submissionBatch,
                  submittedAt: item.submittedAt ?? order.createdAt,
                ),
              )
              .toList(),
          orderType: order.orderType,
          discountPercent: discountPercent,
          taxEnabled: order.taxRate > 0,
          taxRate: order.taxRate,
          tableId: order.tableId,
          tableName: order.tableName,
          customerId: order.customerId,
          customerName: order.customerName,
          note: order.note ?? '',
        );
    context.go('/pos');
  }

  Future<void> _openOpenBillPayment(OrderHistoryItem order) async {
    final draft = await AppBottomSheet.show<_OpenBillPaymentDraft>(
      context,
      title: 'Bayar open bill',
      subtitle: order.receiptNumber,
      child: _OpenBillPaymentForm(order: order),
    );
    if (draft == null || !mounted) return;

    setState(() => _isMutating = true);
    final result = await ref
        .read(orderHistoryProvider.notifier)
        .payOpenBill(
          order: order,
          method: draft.method,
          paymentBreakdown: {draft.method: order.total},
          amountReceived: draft.amountReceived,
          change: draft.change,
        );
    if (!mounted) return;
    if (result.isSuccess) {
      ref.invalidate(customerProvider);
      if (order.customerId != null) {
        ref.invalidate(customerOrderHistoryProvider(order.customerId!));
      }
      await ref
          .read(printerProvider.notifier)
          .autoPrintReceipt(
            order.toPrintData(
              paymentMethod: draft.method,
              paymentBreakdown: {draft.method: order.total},
              amountReceived: draft.amountReceived,
              change: draft.change,
              isReprint: false,
            ),
          );
    }
    if (!mounted) return;
    setState(() => _isMutating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
    if (result.isSuccess && mounted) context.go('/pos');
  }

  Future<void> _openCancellation(OrderHistoryItem order) async {
    final draft = await AppBottomSheet.show<_CancellationDraft>(
      context,
      title: 'Batalkan pesanan',
      subtitle: order.receiptNumber,
      child: _CancellationForm(order: order),
    );
    if (draft == null || !mounted) return;

    setState(() => _isMutating = true);
    final result = await ref
        .read(orderHistoryProvider.notifier)
        .cancelOrder(
          order: order,
          inventoryOutcome: draft.inventoryOutcome,
          reason: draft.reason,
        );
    if (result.isSuccess) {
      ref.invalidate(customerProvider);
      ref.invalidate(kdsOverviewProvider);
      ref.invalidate(kdsNotifierProvider);
      if (order.customerId != null) {
        ref.invalidate(customerOrderHistoryProvider(order.customerId!));
      }
      try {
        await ref.read(tableProvider.notifier).syncFromServer();
      } catch (_) {
        // Order cancellation is already saved; table data can refresh later.
      }
    }
    if (!mounted) return;
    setState(() => _isMutating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
  }

  Future<void> _reprint(
    OrderHistoryItem order, {
    bool receiptOnly = false,
    bool kitchenOnly = false,
  }) async {
    final notifier = ref.read(printerProvider.notifier);
    final printData = order.toPrintData();
    final result = receiptOnly
        ? await notifier.printReceipt(printData)
        : kitchenOnly
        ? await notifier.printKitchenTickets(printData)
        : await notifier.printTransaction(printData);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }
}

class _CancellationForm extends StatefulWidget {
  const _CancellationForm({required this.order});

  final OrderHistoryItem order;

  @override
  State<_CancellationForm> createState() => _CancellationFormState();
}

class _CancellationFormState extends State<_CancellationForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String _inventoryOutcome = 'no_stock_return';
  bool _confirmed = false;

  double get _automaticRefund =>
      math.max(widget.order.total - widget.order.refundedAmount, 0).toDouble();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final financialMessage = widget.order.isOpenBill
        ? 'Open bill belum memiliki pembayaran, jadi tidak ada refund.'
        : _automaticRefund > 0
        ? 'Sisa pembayaran ${currency.format(_automaticRefund)} akan dicatat sebagai refund otomatis.'
        : 'Pembayaran pesanan ini sudah direfund penuh. Tidak ada refund tambahan.';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              color: AppColors.errorSoft,
              borderColor: AppColors.error,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      financialMessage,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _inventoryOutcome,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Perlakuan stok bahan',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'no_stock_return',
                  child: Text('Bahan tetap terpakai'),
                ),
                DropdownMenuItem(
                  value: 'restore_stock',
                  child: Text('Kembalikan bahan ke stok'),
                ),
              ],
              onChanged: (value) => setState(
                () => _inventoryOutcome = value ?? _inventoryOutcome,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Alasan pembatalan',
                prefixIcon: Icon(Icons.notes_rounded),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                final reason = (value ?? '').trim();
                if (reason.isEmpty) return 'Alasan wajib diisi';
                if (reason.length < 3) return 'Alasan minimal 3 karakter';
                return null;
              },
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Saya sudah memeriksa pesanan, pembayaran, dan kondisi bahan.',
              ),
              onChanged: (value) => setState(() => _confirmed = value ?? false),
            ),
            const SizedBox(height: 12),
            AppButton(
              text: 'Konfirmasi pembatalan',
              icon: Icons.cancel_outlined,
              variant: AppButtonVariant.danger,
              onPressed: _confirmed ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _CancellationDraft(
        inventoryOutcome: _inventoryOutcome,
        reason: _reason.text.trim(),
      ),
    );
  }
}

class _CancellationDraft {
  const _CancellationDraft({
    required this.inventoryOutcome,
    required this.reason,
  });

  final String inventoryOutcome;
  final String reason;
}

class _RefundForm extends StatefulWidget {
  const _RefundForm({required this.order});

  final OrderHistoryItem order;

  @override
  State<_RefundForm> createState() => _RefundFormState();
}

class _RefundFormState extends State<_RefundForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  late OrderHistoryLine _item;
  int _quantity = 1;
  String _inventoryOutcome = 'no_stock_return';

  double get _remaining => widget.order.total - widget.order.refundedAmount;

  @override
  void initState() {
    super.initState();
    _item = widget.order.items.firstWhere((item) => item.id != null);
    _amount = TextEditingController();
    _useSuggestedAmount();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.order.items.where((item) => item.id != null).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _item.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Produk',
                prefixIcon: Icon(Icons.restaurant_menu_rounded),
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                final selected = items
                    .where((item) => item.id == id)
                    .firstOrNull;
                if (selected == null) return;
                setState(() {
                  _item = selected;
                  _quantity = 1;
                  _useSuggestedAmount();
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _quantity,
              decoration: const InputDecoration(
                labelText: 'Jumlah',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              items: List.generate(
                _item.quantity,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1} produk'),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _quantity = value ?? _quantity;
                  _useSuggestedAmount();
                });
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Nominal refund',
                prefixText: 'Rp ',
                helperText:
                    'Sisa yang dapat direfund: ${NumberFormat.decimalPattern('id_ID').format(_remaining)}',
              ),
              validator: (value) {
                final amount = double.tryParse(value ?? '') ?? 0;
                if (amount <= 0) return 'Nominal harus lebih dari 0';
                if (amount > _remaining) {
                  return 'Nominal melebihi sisa refund';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _inventoryOutcome,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Dampak ke produksi',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'no_stock_return',
                  child: Text('Refund saja - stok tetap'),
                ),
                DropdownMenuItem(
                  value: 'wrong_discard',
                  child: Text('Salah produksi - dibuang'),
                ),
                DropdownMenuItem(
                  value: 'wrong_remake',
                  child: Text('Salah produksi - buat ulang'),
                ),
              ],
              onChanged: (value) => setState(
                () => _inventoryOutcome = value ?? _inventoryOutcome,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Alasan refund',
                prefixIcon: Icon(Icons.notes_rounded),
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Alasan wajib diisi' : null,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.currency_exchange_rounded),
              label: const Text('Catat refund'),
            ),
          ],
        ),
      ),
    );
  }

  void _useSuggestedAmount() {
    final unitPrice = _item.quantity <= 0 ? 0 : _item.total / _item.quantity;
    final suggested = math.min(unitPrice * _quantity, _remaining);
    _amount.text = suggested.round().toString();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _RefundDraft(
        item: _item,
        quantity: _quantity,
        amount: double.parse(_amount.text),
        inventoryOutcome: _inventoryOutcome,
        reason: _reason.text.trim(),
      ),
    );
  }
}

class _RefundDraft {
  const _RefundDraft({
    required this.item,
    required this.quantity,
    required this.amount,
    required this.inventoryOutcome,
    required this.reason,
  });

  final OrderHistoryLine item;
  final int quantity;
  final double amount;
  final String inventoryOutcome;
  final String reason;
}

class _OrderPrintActions extends StatelessWidget {
  const _OrderPrintActions({
    required this.state,
    required this.isOpenBill,
    required this.isCancelled,
    required this.onReceipt,
    required this.onKitchen,
    required this.onAll,
  });

  final PrinterState state;
  final bool isOpenBill;
  final bool isCancelled;
  final VoidCallback onReceipt;
  final VoidCallback onKitchen;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Cetak ulang', style: theme.textTheme.titleMedium),
            ),
            if (state.isPrinting)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          state.hasAnyPrinter
              ? isCancelled
                    ? 'Bukti pelanggan diberi penanda pembatalan.'
                    : isOpenBill
                    ? 'Tagihan dicetak dengan status belum lunas.'
                    : 'Dokumen cetak ulang diberi penanda salinan.'
              : 'Atur printer kasir dan dapur dari menu Lainnya.',
          style: theme.textTheme.bodySmall,
        ),
        if (state.error != null) ...[
          const SizedBox(height: 8),
          Text(
            state.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final receiptButton = OutlinedButton.icon(
              onPressed: state.hasCashierPrinter && !state.isPrinting
                  ? onReceipt
                  : null,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(
                isCancelled
                    ? 'Bukti pembatalan'
                    : isOpenBill
                    ? 'Tagihan pelanggan'
                    : 'Struk pelanggan',
              ),
            );
            final kitchenButton = OutlinedButton.icon(
              onPressed:
                  !isCancelled &&
                      state.hasProductionPrinter &&
                      !state.isPrinting
                  ? onKitchen
                  : null,
              icon: const Icon(Icons.restaurant_outlined),
              label: const Text('Tiket dapur'),
            );
            if (constraints.maxWidth < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  receiptButton,
                  const SizedBox(height: 8),
                  kitchenButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: receiptButton),
                const SizedBox(width: 8),
                Expanded(child: kitchenButton),
              ],
            );
          },
        ),
        if (!isOpenBill && !isCancelled) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: state.hasAnyPrinter && !state.isPrinting ? onAll : null,
            icon: const Icon(Icons.print_rounded),
            label: const Text('Cetak semua dokumen'),
          ),
        ],
      ],
    );
  }
}

class _OpenBillPaymentForm extends StatefulWidget {
  const _OpenBillPaymentForm({required this.order});

  final OrderHistoryItem order;

  @override
  State<_OpenBillPaymentForm> createState() => _OpenBillPaymentFormState();
}

class _OpenBillPaymentFormState extends State<_OpenBillPaymentForm> {
  final _cash = TextEditingController();
  String _method = 'cash';

  double get _cashAmount =>
      double.tryParse(_cash.text.replaceAll('.', '')) ?? 0;

  bool get _isValid => _method != 'cash' || _cashAmount >= widget.order.total;

  @override
  void initState() {
    super.initState();
    _cash.addListener(_refresh);
  }

  @override
  void dispose() {
    _cash.removeListener(_refresh);
    _cash.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final change = _method == 'cash'
        ? math.max(0, _cashAmount - widget.order.total).toDouble()
        : 0.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              children: [
                _DetailLine(
                  label: 'Total tagihan',
                  value: currency.format(widget.order.total),
                  emphasized: true,
                ),
                if (widget.order.tableName != null) ...[
                  const SizedBox(height: 10),
                  _DetailLine(label: 'Meja', value: widget.order.tableName!),
                ],
                if (widget.order.customerName != null) ...[
                  const SizedBox(height: 10),
                  _DetailLine(
                    label: 'Pelanggan',
                    value: widget.order.customerName!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(
                value: 'cash',
                icon: Icon(Icons.payments_outlined),
                label: Text('Tunai'),
              ),
              ButtonSegment(
                value: 'qris',
                icon: Icon(Icons.qr_code_2_rounded),
                label: Text('QRIS'),
              ),
              ButtonSegment(
                value: 'debit_card',
                icon: Icon(Icons.credit_card_outlined),
                label: Text('Kartu debit'),
              ),
            ],
            selected: {_method},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() => _method = selection.first);
            },
          ),
          if (_method == 'cash') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _cash,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Uang diterima',
                prefixText: 'Rp ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                label: const Text('Uang pas'),
                onPressed: () {
                  _cash.text = widget.order.total.round().toString();
                },
              ),
            ),
            const SizedBox(height: 10),
            _DetailLine(
              label: 'Kembalian',
              value: currency.format(change),
              emphasized: true,
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            text: 'Konfirmasi pembayaran',
            icon: Icons.check_rounded,
            onPressed: _isValid
                ? () => Navigator.pop(
                    context,
                    _OpenBillPaymentDraft(
                      method: _method,
                      amountReceived: _method == 'cash' ? _cashAmount : null,
                      change: change,
                    ),
                  )
                : null,
          ),
          if (!_isValid) ...[
            const SizedBox(height: 8),
            Text(
              'Jumlah tunai belum mencukupi.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpenBillPaymentDraft {
  const _OpenBillPaymentDraft({
    required this.method,
    required this.amountReceived,
    required this.change,
  });

  final String method;
  final double? amountReceived;
  final double change;
}

class _DateRangeToolbar extends StatelessWidget {
  const _DateRangeToolbar({
    required this.label,
    required this.isToday,
    required this.onSelect,
    required this.onToday,
  });

  final String label;
  final bool isToday;
  final VoidCallback onSelect;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('Periode pesanan', style: theme.textTheme.titleMedium),
          ],
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(label, overflow: TextOverflow.ellipsis),
            ),
            if (!isToday) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Kembali ke hari ini',
                onPressed: onToday,
                icon: const Icon(Icons.today_outlined),
              ),
            ],
          ],
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: controls),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            controls,
          ],
        );
      },
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.orderCount,
    required this.revenue,
    required this.pendingCount,
    required this.openBillCount,
    required this.isToday,
  });

  final int orderCount;
  final String revenue;
  final int pendingCount;
  final int openBillCount;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 760
            ? 3
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: isToday ? 'Pesanan hari ini' : 'Pesanan periode',
                value: '$orderCount',
                icon: Icons.receipt_long_outlined,
                iconColor: AppColors.info,
              ),
            ),
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: isToday ? 'Penjualan hari ini' : 'Penjualan periode',
                value: revenue,
                icon: Icons.payments_outlined,
                iconColor: AppColors.success,
              ),
            ),
            SizedBox(
              width: width,
              height: 112,
              child: AppMetricCard(
                title: 'Open bill aktif',
                value: '$openBillCount',
                icon: Icons.bookmark_added_outlined,
                iconColor: openBillCount == 0
                    ? AppColors.success
                    : AppColors.info,
              ),
            ),
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

class _PaymentSummaryTable extends StatelessWidget {
  const _PaymentSummaryTable({
    required this.summaries,
    required this.currency,
    required this.isToday,
    required this.cashOverview,
    required this.onOpenCash,
  });

  final List<_PaymentMethodSummary> summaries;
  final NumberFormat currency;
  final bool isToday;
  final AsyncValue<CashOverview> cashOverview;
  final VoidCallback onOpenCash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isToday
                        ? 'Metode pembayaran hari ini'
                        : 'Metode pembayaran periode',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text('Transaksi', style: theme.textTheme.labelMedium),
                const SizedBox(width: 28),
                SizedBox(
                  width: 112,
                  child: Text(
                    'Nominal',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ...summaries.indexed.map((entry) {
            final (index, summary) = entry;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _paymentColor(summary.method),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _paymentIcon(summary.method),
                          size: 19,
                          color: _paymentTextColor(summary.method),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          summary.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${summary.transactionCount}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 112,
                        child: Text(
                          currency.format(summary.amount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (index != summaries.length - 1)
                  Divider(
                    height: 1,
                    indent: 60,
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            );
          }),
          if (isToday) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            _CashSessionReport(
              overview: cashOverview,
              currency: currency,
              onOpenCash: onOpenCash,
            ),
          ],
        ],
      ),
    );
  }
}

class _CashSessionReport extends StatelessWidget {
  const _CashSessionReport({
    required this.overview,
    required this.currency,
    required this.onOpenCash,
  });

  final AsyncValue<CashOverview> overview;
  final NumberFormat currency;
  final VoidCallback onOpenCash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return overview.when(
      loading: () => const _CashReportStatus(
        icon: Icons.hourglass_top_rounded,
        title: 'Uang Kas berjalan',
        message: 'Memuat sesi kas aktif...',
      ),
      error: (_, _) => _CashReportStatus(
        icon: Icons.cloud_off_outlined,
        title: 'Laporan kas belum tersedia',
        message: 'Ketuk untuk mencoba dari halaman pengelolaan kas.',
        onTap: onOpenCash,
      ),
      data: (data) {
        final shift = data.currentShift;
        if (shift == null) {
          return _CashReportStatus(
            icon: Icons.point_of_sale_outlined,
            title: 'Belum ada sesi kas aktif',
            message: 'Buka kas untuk mulai mencatat uang masuk dan keluar.',
            onTap: onOpenCash,
          );
        }

        return InkWell(
          onTap: onOpenCash,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Uang Kas berjalan',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${shift.number} • dibuka ${AppDateFormatter.time(shift.startedAt.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Saldo Uang Kas',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      currency.format(shift.summary.cashFundBalance),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Buka pengelolaan kas',
                  onPressed: onOpenCash,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CashReportStatus extends StatelessWidget {
  const _CashReportStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodSummary {
  const _PaymentMethodSummary({
    required this.method,
    required this.label,
    required this.transactionCount,
    required this.amount,
  });

  final String method;
  final String label;
  final int transactionCount;
  final double amount;
}

List<_PaymentMethodSummary> _summarizePayments(
  Iterable<OrderHistoryItem> orders,
) {
  final amounts = <String, double>{'cash': 0, 'qris': 0, 'debit': 0};
  final counts = <String, int>{'cash': 0, 'qris': 0, 'debit': 0};

  for (final order in orders) {
    final breakdown = order.paymentBreakdown.isNotEmpty
        ? order.paymentBreakdown
        : {order.paymentMethod: order.total};
    final methodsInOrder = <String>{};
    for (final entry in breakdown.entries) {
      final method = _normalizedPaymentMethod(entry.key);
      if (method == null || entry.value <= 0) continue;
      amounts[method] = (amounts[method] ?? 0) + entry.value;
      methodsInOrder.add(method);
    }
    for (final method in methodsInOrder) {
      counts[method] = (counts[method] ?? 0) + 1;
    }
  }

  return [
    _PaymentMethodSummary(
      method: 'cash',
      label: 'Tunai',
      transactionCount: counts['cash']!,
      amount: amounts['cash']!,
    ),
    _PaymentMethodSummary(
      method: 'qris',
      label: 'QRIS',
      transactionCount: counts['qris']!,
      amount: amounts['qris']!,
    ),
    _PaymentMethodSummary(
      method: 'debit',
      label: 'Kartu debit',
      transactionCount: counts['debit']!,
      amount: amounts['debit']!,
    ),
  ];
}

String? _normalizedPaymentMethod(String method) =>
    switch (method.trim().toLowerCase()) {
      'cash' => 'cash',
      'qris' => 'qris',
      'debit' || 'debit_card' || 'card' => 'debit',
      _ => null,
    };

bool _isSingleDay(DateTimeRange range) =>
    DateUtils.isSameDay(range.start, range.end);

String _dateRangeLabel(DateTimeRange range) {
  if (_isSingleDay(range)) {
    return DateUtils.isSameDay(range.start, DateTime.now())
        ? 'Hari ini, ${AppDateFormatter.shortDate(range.start)}'
        : AppDateFormatter.shortDate(range.start);
  }
  return '${AppDateFormatter.shortDate(range.start)} - '
      '${AppDateFormatter.shortDate(range.end)}';
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
                        order.isOpenBill
                            ? order.openBillHeading
                            : order.receiptNumber,
                        maxLines: order.isOpenBill ? 2 : 1,
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
                  order.isOpenBill
                      ? AppDateFormatter.longDateTime(order.createdAt.toLocal())
                      : '${_orderTypeLabel(order.orderType)} · ${order.itemCount} item · $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (order.isPending && !order.isOpenBill) ...[
                  const SizedBox(height: 7),
                  const AppBadge(
                    text: 'Menunggu sinkron',
                    color: AppColors.warningSoft,
                    textColor: AppColors.warning,
                    icon: Icons.cloud_upload_outlined,
                  ),
                ],
                if (!order.isOpenBill && !order.isVoided) ...[
                  const SizedBox(height: 7),
                  AppBadge(
                    text: order.paymentSummary,
                    color: _paymentColor(order.paymentMethods.firstOrNull),
                    textColor: _paymentTextColor(
                      order.paymentMethods.firstOrNull,
                    ),
                    icon: _paymentIcon(order.paymentMethods.firstOrNull),
                  ),
                ],
                if (order.isVoided) ...[
                  const SizedBox(height: 7),
                  const AppBadge(
                    text: 'Dibatalkan',
                    color: AppColors.errorSoft,
                    textColor: AppColors.error,
                    icon: Icons.cancel_outlined,
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
        Expanded(
          child: Text(value, textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }
}

String _orderTypeLabel(String value) => switch (value) {
  'dine_in' => 'Makan di tempat',
  'delivery' => 'Pesan antar',
  _ => 'Bawa pulang',
};

IconData _paymentIcon(String? method) => switch (method) {
  'cash' => Icons.payments_outlined,
  'qris' => Icons.qr_code_2_rounded,
  'debit' || 'debit_card' || 'card' => Icons.credit_card_outlined,
  _ => Icons.account_balance_wallet_outlined,
};

Color _paymentColor(String? method) => switch (method) {
  'cash' => AppColors.successSoft,
  'qris' => AppColors.infoSoft,
  'debit' || 'debit_card' || 'card' => AppColors.warningSoft,
  _ => AppColors.surfaceMuted,
};

Color _paymentTextColor(String? method) => switch (method) {
  'cash' => AppColors.success,
  'qris' => AppColors.info,
  'debit' || 'debit_card' || 'card' => AppColors.warning,
  _ => AppColors.textSecondary,
};
