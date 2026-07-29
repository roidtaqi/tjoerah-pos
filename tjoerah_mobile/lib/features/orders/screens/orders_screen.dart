import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../customers/providers/customer_provider.dart';
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
            onPressed: _isMutating
                ? null
                : () => ref.read(orderHistoryProvider.notifier).refresh(),
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
    final openBills = orders.where((order) => order.isOpenBill).length;
    final paidToday = todayOrders.where((order) => order.isPaid);
    final revenue = paidToday.fold<double>(
      0,
      (sum, order) => sum + order.total - order.refundedAmount,
    );
    final normalized = _query.trim().toLowerCase();
    final filtered = orders.where((order) {
      final matchesFilter = switch (_filter) {
        _OrderFilter.all => true,
        _OrderFilter.openBill => order.isOpenBill,
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
            orderCount: paidToday.length,
            revenue: _currency.format(revenue),
            pendingCount: pending,
            openBillCount: openBills,
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
              value: order.isOpenBill
                  ? 'Belum dibayar'
                  : _paymentLabel(order.paymentMethod),
            ),
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
            if (order.isOpenBill) ...[
              const SizedBox(height: 18),
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
    required this.onReceipt,
    required this.onKitchen,
    required this.onAll,
  });

  final PrinterState state;
  final bool isOpenBill;
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
              ? isOpenBill
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
              label: Text(isOpenBill ? 'Tagihan pelanggan' : 'Struk pelanggan'),
            );
            final kitchenButton = OutlinedButton.icon(
              onPressed: state.hasProductionPrinter && !state.isPrinting
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
        if (!isOpenBill) ...[
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
                value: 'card',
                icon: Icon(Icons.credit_card_outlined),
                label: Text('Kartu'),
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

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.orderCount,
    required this.revenue,
    required this.pendingCount,
    required this.openBillCount,
  });

  final int orderCount;
  final String revenue;
  final int pendingCount;
  final int openBillCount;

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
                if (order.isOpenBill) ...[
                  const SizedBox(height: 7),
                  const AppBadge(
                    text: 'Belum dibayar',
                    color: AppColors.infoSoft,
                    textColor: AppColors.info,
                    icon: Icons.bookmark_added_outlined,
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
  'card' => 'Kartu',
  'debit' => 'Kartu debit',
  'credit_card' => 'Kartu kredit',
  'ewallet' => 'Dompet digital',
  'split' => 'Pembayaran terpisah',
  'open_bill' => 'Belum dibayar',
  _ => value.toUpperCase(),
};
