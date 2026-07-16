import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../providers/cart_provider.dart';
import '../screens/payment_screen.dart';

class OrderCart extends ConsumerWidget {
  const OrderCart({super.key, this.scrollController, this.onClose});

  final ScrollController? scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);

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
                    Text('Pesanan saat ini', style: theme.textTheme.titleLarge),
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
                      ],
                    ),
                  ],
                ),
              ),
              if (cart.items.isNotEmpty)
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
        if (cart.items.isEmpty)
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
        else ...[
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: cart.items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 17, color: theme.colorScheme.outlineVariant),
              itemBuilder: (context, index) =>
                  _CartItemRow(item: cart.items[index]),
            ),
          ),
          Divider(color: theme.colorScheme.outline),
          _OrderActions(cart: cart),
          Divider(color: theme.colorScheme.outline),
          _OrderTotals(cart: cart),
        ],
      ],
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _showCustomer(context, ref),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
            label: Text(cart.customerName ?? 'Pelanggan'),
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
    final controller = TextEditingController(text: cart.customerName);
    await AppBottomSheet.show<void>(
      context,
      title: 'Pelanggan',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama pelanggan',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              text: 'Simpan pelanggan',
              onPressed: () {
                ref.read(cartProvider.notifier).setCustomer(controller.text);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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

class _OrderTotals extends StatelessWidget {
  const _OrderTotals({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 6),
            _TotalRow(label: 'Pajak 11%', value: currency.format(cart.tax)),
            const SizedBox(height: 12),
            _TotalRow(
              label: 'Total',
              value: currency.format(cart.total),
              emphasize: true,
            ),
            const SizedBox(height: 16),
            AppButton(
              text: 'Bayar ${currency.format(cart.total)}',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => showPaymentFlow(context),
            ),
          ],
        ),
      ),
    );
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
