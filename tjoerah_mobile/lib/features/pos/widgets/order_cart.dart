import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/printer/print_job.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../customers/providers/customer_provider.dart';
import '../../orders/providers/order_history_provider.dart';
import '../../settings/providers/printer_provider.dart';
import '../providers/cart_provider.dart';
import '../repositories/order_repository.dart';
import '../screens/payment_screen.dart';

class OrderCart extends ConsumerWidget {
  const OrderCart({super.key, this.scrollController, this.onClose});

  final ScrollController? scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final useFlexibleFooter =
        MediaQuery.textScalerOf(context).scale(16) > 18 ||
        MediaQuery.sizeOf(context).height < 560;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cart.isEditingOpenBill
                          ? cart.openBill!.label
                          : 'Pesanan saat ini',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AppBadge(
                          text: cart.orderTypeLabel,
                          icon: _orderTypeIcon(cart.orderType),
                        ),
                        if (cart.tableName != null)
                          AppBadge(
                            text: cart.tableName!,
                            icon: Icons.table_restaurant_outlined,
                          ),
                        if (cart.isEditingOpenBill)
                          AppBadge(
                            text: cart.openBill!.receiptNumber,
                            icon: Icons.bookmark_added_outlined,
                          ),
                        if (cart.isEditingOpenBill)
                          AppBadge(
                            text: AppDateFormatter.longDateTime(
                              cart.openBill!.createdAt.toLocal(),
                            ),
                            icon: Icons.schedule_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (cart.items.isNotEmpty || cart.submittedItems.isNotEmpty)
                IconButton(
                  tooltip: 'Kosongkan pesanan',
                  onPressed: () => _confirmClear(context, ref),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              if (onClose != null)
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        Divider(color: theme.colorScheme.outline),
        if (cart.items.isEmpty && cart.submittedItems.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 36,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text('Belum ada item', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Ketuk produk untuk menambahkannya.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (useFlexibleFooter) ...[
          Expanded(flex: 2, child: _buildItemList(cart, theme)),
          Divider(color: theme.colorScheme.outline),
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _OrderActions(cart: cart),
                  Divider(color: theme.colorScheme.outline),
                  _OrderTotals(cart: cart),
                ],
              ),
            ),
          ),
        ] else ...[
          Expanded(child: _buildItemList(cart, theme)),
          Divider(color: theme.colorScheme.outline),
          _OrderActions(cart: cart),
          Divider(color: theme.colorScheme.outline),
          _OrderTotals(cart: cart),
        ],
      ],
    );
  }

  Widget _buildItemList(CartState cart, ThemeData theme) {
    if (cart.submittedItems.isNotEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Text('Sudah dikirim', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          ...cart.submittedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SubmittedCartItemRow(item: item),
            ),
          ),
          Divider(height: 24, color: theme.colorScheme.outlineVariant),
          Row(
            children: [
              Expanded(
                child: Text('Tambahan baru', style: theme.textTheme.labelLarge),
              ),
              AppBadge(
                text: '${cart.items.length} item',
                icon: Icons.add_shopping_cart_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (cart.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Belum ada tambahan.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            ...cart.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CartItemRow(item: item),
              ),
            ),
        ],
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: cart.items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 17, color: theme.colorScheme.outlineVariant),
      itemBuilder: (context, index) => _CartItemRow(item: cart.items[index]),
    );
  }

  IconData _orderTypeIcon(String type) => switch (type) {
    'dine_in' => Icons.restaurant_outlined,
    'delivery' => Icons.delivery_dining_outlined,
    _ => Icons.takeout_dining_outlined,
  };

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kosongkan pesanan?'),
        content: const Text('Semua item dan penyesuaian akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kosongkan'),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(cartProvider.notifier).clearCart();
  }
}

class _SubmittedCartItemRow extends StatelessWidget {
  const _SubmittedCartItemRow({required this.item});

  final SubmittedCartItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final time = DateFormat('HH:mm').format(item.submittedAt.toLocal());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 32, child: Text('${item.quantity}x')),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Batch ${item.submissionBatch} · dikirim $time',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(currency.format(item.total), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _CartItemRow extends ConsumerWidget {
  const _CartItemRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                currency.format(item.total),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (item.isManual) ...[
                const SizedBox(height: 5),
                const AppBadge(
                  text: 'Item manual',
                  icon: Icons.edit_note_rounded,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                tooltip: item.quantity == 1 ? 'Hapus item' : 'Kurangi jumlah',
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .updateQuantity(item.productId, item.quantity - 1),
                icon: Icon(
                  item.quantity == 1
                      ? Icons.delete_outline_rounded
                      : Icons.remove_rounded,
                  size: 19,
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${item.quantity}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Tambah jumlah',
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .updateQuantity(item.productId, item.quantity + 1),
                icon: const Icon(Icons.add_rounded, size: 19),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderActions extends ConsumerWidget {
  const _OrderActions({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final customerName = cart.customerName?.trim();
    final hasCustomer = customerName != null && customerName.isNotEmpty;
    final customerButton = hasCustomer
        ? FilledButton.tonalIcon(
            onPressed: () => _showCustomer(context, ref),
            icon: const Icon(Icons.person_rounded, size: 19),
            label: Text(
              customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        : TextButton.icon(
            onPressed: () => _showCustomer(context, ref),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
            label: const Text('Pilih pelanggan'),
          );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: customerButton,
          ),
          TextButton.icon(
            onPressed: () => _showDiscount(context, ref),
            icon: const Icon(Icons.percent_rounded, size: 19),
            label: Text(
              cart.discountPercent > 0
                  ? '${cart.discountPercent.toStringAsFixed(0)}%'
                  : 'Diskon',
            ),
          ),
          TextButton.icon(
            onPressed: () => _showNote(context, ref),
            icon: const Icon(Icons.notes_rounded, size: 19),
            label: Text(cart.note.isEmpty ? 'Catatan' : 'Catatan aktif'),
          ),
          if (cart.discountPercent > 0 || cart.note.isNotEmpty)
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: theme.colorScheme.secondary,
            ),
        ],
      ),
    );
  }

  Future<void> _showDiscount(BuildContext context, WidgetRef ref) async {
    final options = [0.0, 5.0, 10.0, 15.0, 20.0];
    await AppBottomSheet.show<void>(
      context,
      title: 'Terapkan diskon',
      subtitle: 'Diskon berlaku untuk seluruh pesanan.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (value) => ChoiceChip(
                  label: Text(
                    value == 0 ? 'Tanpa diskon' : '${value.toInt()}%',
                  ),
                  selected: cart.discountPercent == value,
                  onSelected: (_) {
                    ref.read(cartProvider.notifier).setDiscount(value);
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _showCustomer(BuildContext context, WidgetRef ref) async {
    await AppBottomSheet.show<void>(
      context,
      title: 'Pilih pelanggan',
      subtitle: 'Transaksi akan masuk ke riwayat pelanggan.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: Consumer(
          builder: (context, ref, _) {
            final customers = ref.watch(customerProvider);
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('Pelanggan umum'),
                  trailing: cart.customerId == null
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () {
                    ref.read(cartProvider.notifier).setCustomer(null);
                    Navigator.pop(context);
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: customers.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (_, _) => Center(
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(customerProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Muat ulang pelanggan'),
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const Center(
                            child: Text('Belum ada pelanggan tersimpan.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final customer = items[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    customer.name
                                        .trim()
                                        .characters
                                        .first
                                        .toUpperCase(),
                                  ),
                                ),
                                title: Text(
                                  customer.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  customer.phone ??
                                      customer.email ??
                                      'Tanpa kontak',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: cart.customerId == customer.id
                                    ? const Icon(Icons.check_circle_rounded)
                                    : null,
                                onTap: () {
                                  ref
                                      .read(cartProvider.notifier)
                                      .setCustomer(
                                        customer.name,
                                        id: customer.id,
                                      );
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/customers');
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Kelola pelanggan'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showNote(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: cart.note);
    await AppBottomSheet.show<void>(
      context,
      title: 'Catatan pesanan',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 180,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Contoh: tanpa sedotan, bungkus terpisah',
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              text: 'Simpan catatan',
              onPressed: () {
                ref.read(cartProvider.notifier).setNote(controller.text);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}

class _OrderTotals extends ConsumerStatefulWidget {
  const _OrderTotals({required this.cart});

  final CartState cart;

  @override
  ConsumerState<_OrderTotals> createState() => _OrderTotalsState();
}

class _OrderTotalsState extends ConsumerState<_OrderTotals> {
  bool _isSavingOpenBill = false;

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _TotalRow(label: 'Subtotal', value: currency.format(cart.subtotal)),
            if (cart.discount > 0) ...[
              const SizedBox(height: 6),
              _TotalRow(
                label: 'Diskon',
                value: '-${currency.format(cart.discount)}',
                color: theme.colorScheme.secondary,
              ),
            ],
            if (cart.taxEnabled && cart.taxRate > 0) ...[
              const SizedBox(height: 6),
              _TotalRow(
                label: 'Pajak ${_percentage(cart.taxRate)}',
                value: currency.format(cart.tax),
              ),
            ],
            const SizedBox(height: 12),
            _TotalRow(
              label: 'Total',
              value: currency.format(cart.total),
              emphasize: true,
            ),
            if (cart.isEditingOpenBill) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.bookmark_added_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${cart.items.length} item baru akan disimpan ke '
                      '${cart.openBill!.receiptNumber}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (!cart.isEditingOpenBill || cart.items.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSavingOpenBill ? null : _saveOpenBill,
                  icon: _isSavingOpenBill
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_add_outlined),
                  label: Text(
                    _isSavingOpenBill
                        ? cart.isEditingOpenBill
                              ? 'Menyimpan tambahan...'
                              : 'Menyimpan open bill...'
                        : cart.isEditingOpenBill
                        ? 'Simpan tambahan ke open bill'
                        : 'Simpan sebagai open bill',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            AppButton(
              text: cart.isEditingOpenBill && cart.items.isNotEmpty
                  ? 'Simpan & bayar ${currency.format(cart.total)}'
                  : 'Bayar ${currency.format(cart.total)}',
              icon: cart.isEditingOpenBill
                  ? Icons.payments_outlined
                  : Icons.arrow_forward_rounded,
              isLoading: cart.isEditingOpenBill && _isSavingOpenBill,
              onPressed: _isSavingOpenBill
                  ? null
                  : cart.isEditingOpenBill
                  ? _payOpenBill
                  : () => showPaymentFlow(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveOpenBill() async {
    final cart = widget.cart;
    if (cart.isEditingOpenBill) {
      await _appendOpenBill(cart);
      return;
    }
    final openBillLabel = await _requestOpenBillLabel(cart);
    if (openBillLabel == null || !mounted) return;

    setState(() => _isSavingOpenBill = true);
    try {
      final created = await OrderRepository().createOpenBill(
        items: cart.items,
        subtotal: cart.subtotal,
        discount: cart.discount,
        tax: cart.tax,
        total: cart.total,
        orderType: cart.orderType,
        tableId: cart.tableId,
        tableName: cart.tableName,
        note: cart.note.isNotEmpty ? cart.note : 'Open bill: $openBillLabel',
        customerId: cart.customerId,
        customerName: cart.customerName,
        openBillLabel: openBillLabel,
      );
      final printData = TransactionPrintData(
        orderId: created.id,
        receiptNumber: created.receiptNumber,
        createdAt: created.createdAt,
        orderTypeLabel: cart.orderTypeLabel,
        tableName: cart.tableName,
        customerName: cart.customerName,
        note: cart.note,
        paymentMethod: 'open_bill',
        paymentBreakdown: const {},
        items: cart.items
            .map(
              (item) => PrintOrderItem(
                name: item.name,
                quantity: item.quantity,
                unitPrice: item.price,
                station: item.station,
              ),
            )
            .toList(),
        subtotal: cart.subtotal,
        discount: cart.discount,
        tax: cart.tax,
        total: cart.total,
        isSynced: created.isSynced,
      );
      ref.invalidate(orderHistoryProvider);
      final printer = ref.read(printerProvider.notifier);
      await printer.autoPrintKitchenTickets(printData);
      if (!mounted) return;
      final printBill = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final canPrint = ref.read(printerProvider).hasCashierPrinter;
          return AlertDialog(
            icon: const Icon(Icons.bookmark_added_outlined),
            title: const Text('Open bill tersimpan'),
            content: Text(
              created.isSynced
                  ? 'Open bill sudah tersimpan. Cetak tagihan belum lunas untuk pelanggan bila diperlukan.'
                  : 'Pesanan tersimpan di perangkat dan akan dikirim ke server saat sinkronisasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Selesai'),
              ),
              FilledButton.icon(
                onPressed: canPrint
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Cetak tagihan'),
              ),
            ],
          );
        },
      );
      if (printBill == true) {
        await printer.printReceipt(printData);
      }
      ref.read(cartProvider.notifier).clearCart();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created.isSynced
                ? 'Open bill ${created.receiptNumber} tersimpan dan dikirim ke dapur.'
                : 'Open bill tersimpan di perangkat dan akan dikirim saat sinkronisasi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open bill belum dapat disimpan: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingOpenBill = false);
    }
  }

  Future<void> _payOpenBill() async {
    final cart = widget.cart;
    if (cart.items.isNotEmpty) {
      final saved = await _appendOpenBill(cart, continueToPayment: true);
      if (!saved || !mounted) return;
    }
    if (mounted) await showPaymentFlow(context);
  }

  Future<String?> _requestOpenBillLabel(CartState cart) async {
    final controller = TextEditingController(
      text: cart.customerName ?? cart.tableName ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Simpan open bill'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Nama, ciri pelanggan, atau tempat duduk',
                    prefixIcon: Icon(Icons.person_pin_circle_outlined),
                  ),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'Keterangan open bill wajib diisi'
                      : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Produk bar atau dapur akan dikirim ke stasiun produksi.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            icon: const Icon(Icons.send_outlined),
            label: const Text('Simpan & kirim'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _appendOpenBill(
    CartState cart, {
    bool continueToPayment = false,
  }) async {
    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan setidaknya satu produk baru.')),
      );
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          continueToPayment
              ? 'Simpan tambahan & lanjut bayar?'
              : 'Simpan tambahan ke open bill?',
        ),
        content: Text(
          '${cart.items.length} item baru akan disimpan pada '
          '${cart.openBill!.receiptNumber}. Item bar atau dapur juga dikirim '
          'ke stasiun produksi sebagai batch baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_outlined),
            label: Text(
              continueToPayment ? 'Simpan & lanjut bayar' : 'Simpan & kirim',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    setState(() => _isSavingOpenBill = true);
    try {
      final newItems = [...cart.items];
      final batch = await OrderRepository().appendOpenBill(
        serverId: cart.openBill!.serverId,
        receiptNumber: cart.openBill!.receiptNumber,
        items: newItems,
      );
      ref
          .read(cartProvider.notifier)
          .markOpenBillItemsSubmitted(submissionBatch: batch);
      await ref.read(orderHistoryProvider.notifier).refresh();
      final newSubtotal = newItems.fold<double>(
        0,
        (sum, item) => sum + item.total,
      );
      final printData = TransactionPrintData(
        orderId: cart.openBill!.serverId,
        receiptNumber: cart.openBill!.receiptNumber,
        createdAt: DateTime.now(),
        orderTypeLabel: cart.orderTypeLabel,
        tableName: cart.tableName,
        customerName: cart.customerName,
        note: 'Tambahan batch $batch',
        paymentMethod: 'open_bill',
        paymentBreakdown: const {},
        items: newItems
            .map(
              (item) => PrintOrderItem(
                name: item.name,
                quantity: item.quantity,
                unitPrice: item.price,
                station: item.station,
              ),
            )
            .toList(),
        subtotal: newSubtotal,
        discount: 0,
        tax: 0,
        total: newSubtotal,
        isSynced: true,
      );
      String? printWarning;
      try {
        final printResult = await ref
            .read(printerProvider.notifier)
            .autoPrintKitchenTickets(printData);
        if (printResult.failures.isNotEmpty) {
          printWarning = printResult.message;
        }
      } catch (_) {
        printWarning = 'Tiket produksi belum berhasil dicetak.';
      }
      if (!mounted) return true;
      if (!continueToPayment || printWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              printWarning == null
                  ? 'Tambahan batch $batch tersimpan di ${cart.openBill!.receiptNumber} dan dikirim ke produksi.'
                  : 'Tambahan batch $batch tersimpan. $printWarning',
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tambahan belum dapat dikirim: $message')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSavingOpenBill = false);
    }
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.color,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleLarge
        : theme.textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(
          value,
          style: style?.copyWith(
            color: color,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _percentage(double value) {
  final formatted = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return '$formatted%';
}
