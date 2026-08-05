import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_search_bar.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../../orders/models/order_history_model.dart';
import '../../orders/providers/order_history_provider.dart';
import '../../settings/providers/printer_provider.dart';
import '../../settings/providers/transaction_settings_provider.dart';
import '../../../core/printer/print_job.dart';
import '../repositories/order_repository.dart';
import '../widgets/category_chips.dart';
import '../widgets/floating_cart.dart';
import '../widgets/order_cart.dart';
import '../widgets/product_grid.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = AppBreakpoints.isWide(context);
    final cart = ref.watch(cartProvider);
    final transactionSettings = ref.watch(transactionSettingsProvider);
    final openBillCount =
        ref
            .watch(orderHistoryProvider)
            .value
            ?.where((order) => order.isOpenBill)
            .length ??
        0;
    final settings = transactionSettings.asData?.value;
    if (settings != null &&
        (cart.taxEnabled != settings.taxEnabled ||
            cart.taxRate != settings.taxRate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(cartProvider.notifier)
            .setTaxSettings(
              enabled: settings.taxEnabled,
              rate: settings.taxRate,
            );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tjoerah POS'),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 760)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: AppBadge(
                text: 'Siap offline',
                icon: Icons.cloud_done_outlined,
              ),
            ),
          const SizedBox(width: 4),
          if (MediaQuery.sizeOf(context).width >= 760)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton.icon(
                onPressed: () => _showOpenBills(context, ref),
                icon: const Icon(Icons.bookmarks_outlined),
                label: Text('Open bill ($openBillCount)'),
              ),
            )
          else
            IconButton(
              tooltip: 'Open bill aktif',
              onPressed: () => _showOpenBills(context, ref),
              icon: Badge(
                isLabelVisible: openBillCount > 0,
                label: Text('$openBillCount'),
                child: const Icon(Icons.bookmarks_outlined),
              ),
            ),
          IconButton(
            tooltip: 'Kas outlet',
            onPressed: () => context.push('/cash'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(
            tooltip: 'Sinkronkan katalog',
            onPressed: () => _syncCatalog(context, ref),
            icon: const Icon(Icons.sync_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu pesanan',
            onSelected: (value) {
              if (value == 'clear') ref.read(cartProvider.notifier).clearCart();
              if (value == 'tables') context.push('/tables');
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'tables',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.table_restaurant_outlined),
                  title: Text('Pilih meja'),
                ),
              ),
              if (cart.items.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Kosongkan pesanan'),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: isWide ? _TabletPos(cart: cart) : const _PhonePos(),
    );
  }

  Future<void> _syncCatalog(BuildContext context, WidgetRef ref) async {
    await ref.read(catalogProvider.notifier).syncFromServer();
    if (!context.mounted) return;
    final result = ref.read(catalogProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.hasError
              ? 'Sinkronisasi gagal. Katalog lokal tetap dapat digunakan.'
              : 'Katalog berhasil diperbarui.',
        ),
      ),
    );
  }

  Future<void> _showOpenBills(BuildContext context, WidgetRef ref) async {
    final selected = await AppBottomSheet.show<OrderHistoryItem>(
      context,
      title: 'Open bill aktif',
      subtitle: 'Pilih pelanggan untuk membuka atau menerima pembayaran.',
      child: const _OpenBillPicker(),
    );
    if (selected == null || !context.mounted) return;
    if (!await _prepareCartForSwitch(context, ref)) return;
    _activateOpenBill(ref, selected);
  }

  Future<bool> _prepareCartForSwitch(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return true;
    if (cart.isEditingOpenBill) {
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Simpan tambahan?'),
          content: Text(
            '${cart.items.length} item baru belum tersimpan pada '
            '${cart.openBill!.label}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Tetap di sini'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Simpan tambahan'),
            ),
          ],
        ),
      );
      if (save != true || !context.mounted) return false;
      return _appendCurrentOpenBill(context, ref, cart);
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pesanan belum disimpan'),
        content: const Text(
          'Simpan pesanan saat ini sebagai open bill sebelum berpindah pelanggan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Kosongkan'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Simpan open bill'),
          ),
        ],
      ),
    );
    if (action == 'discard') {
      ref.read(cartProvider.notifier).clearCart();
      return true;
    }
    if (action != 'save' || !context.mounted) return false;
    return _saveCurrentAsOpenBill(context, ref, cart);
  }

  Future<bool> _saveCurrentAsOpenBill(
    BuildContext context,
    WidgetRef ref,
    CartState cart,
  ) async {
    final label = await _promptOpenBillLabel(context, cart);
    if (label == null || !context.mounted) return false;
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
        note: cart.note,
        customerId: cart.customerId,
        customerName: cart.customerName,
        openBillLabel: label,
      );
      final printData = _printDataForCart(
        cart,
        orderId: created.id,
        receiptNumber: created.receiptNumber,
        createdAt: created.createdAt,
        isSynced: created.isSynced,
      );
      try {
        await ref
            .read(printerProvider.notifier)
            .autoPrintKitchenTickets(printData);
      } catch (_) {}
      ref.read(cartProvider.notifier).clearCart();
      await ref.read(orderHistoryProvider.notifier).refresh();
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open bill belum dapat disimpan: $error')),
        );
      }
      return false;
    }
  }

  Future<bool> _appendCurrentOpenBill(
    BuildContext context,
    WidgetRef ref,
    CartState cart,
  ) async {
    try {
      final items = [...cart.items];
      final batch = await OrderRepository().appendOpenBill(
        serverId: cart.openBill!.serverId,
        receiptNumber: cart.openBill!.receiptNumber,
        items: items,
      );
      final printData = _printDataForCart(
        cart.copyWith(items: items, submittedItems: const []),
        orderId: cart.openBill!.serverId,
        receiptNumber: cart.openBill!.receiptNumber,
        createdAt: DateTime.now(),
        isSynced: true,
        note: 'Tambahan batch $batch',
      );
      try {
        await ref
            .read(printerProvider.notifier)
            .autoPrintKitchenTickets(printData);
      } catch (_) {}
      ref.read(cartProvider.notifier).clearCart();
      await ref.read(orderHistoryProvider.notifier).refresh();
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tambahan belum dapat disimpan: $error')),
        );
      }
      return false;
    }
  }

  void _activateOpenBill(WidgetRef ref, OrderHistoryItem order) {
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
  }
}

class _OpenBillPicker extends ConsumerStatefulWidget {
  const _OpenBillPicker();

  @override
  ConsumerState<_OpenBillPicker> createState() => _OpenBillPickerState();
}

class _OpenBillPickerState extends ConsumerState<_OpenBillPicker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orderHistoryProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderHistoryProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.read(orderHistoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Muat ulang'),
          ),
        ),
        data: (orders) {
          final openBills = orders.where((order) => order.isOpenBill).toList();
          if (openBills.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Tidak ada open bill aktif.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            itemCount: openBills.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final order = openBills[index];
              return ListTile(
                minTileHeight: 76,
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text(
                  order.openBillHeading,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  AppDateFormatter.longDateTime(order.createdAt.toLocal()),
                ),
                trailing: Text(
                  _posCurrency(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                enabled: order.serverId != null && !order.isPending,
                onTap: () => Navigator.pop(context, order),
              );
            },
          );
        },
      ),
    );
  }
}

Future<String?> _promptOpenBillLabel(
  BuildContext context,
  CartState cart,
) async {
  final controller = TextEditingController(
    text: cart.customerName ?? cart.tableName ?? '',
  );
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Identitas open bill'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama, ciri pelanggan, atau tempat duduk',
            prefixIcon: Icon(Icons.person_pin_circle_outlined),
          ),
          validator: (value) => (value ?? '').trim().length < 2
              ? 'Keterangan open bill wajib diisi'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(dialogContext, controller.text.trim());
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

TransactionPrintData _printDataForCart(
  CartState cart, {
  required String orderId,
  required String receiptNumber,
  required DateTime createdAt,
  required bool isSynced,
  String? note,
}) {
  return TransactionPrintData(
    orderId: orderId,
    receiptNumber: receiptNumber,
    createdAt: createdAt,
    orderTypeLabel: cart.orderTypeLabel,
    tableName: cart.tableName,
    customerName: cart.customerName,
    note: note ?? cart.note,
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
    subtotal: cart.newItemsSubtotal,
    discount: 0,
    tax: 0,
    total: cart.newItemsSubtotal,
    isSynced: isSynced,
  );
}

String _posCurrency(double value) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
).format(value);

class _PhonePos extends StatelessWidget {
  const _PhonePos();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        _CatalogPane(),
        Positioned(left: 0, right: 0, bottom: 0, child: FloatingCartPanel()),
      ],
    );
  }
}

class _TabletPos extends StatelessWidget {
  const _TabletPos({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: _CatalogPane()),
        VerticalDivider(width: 1, color: theme.colorScheme.outline),
        SizedBox(
          width: MediaQuery.sizeOf(context).width >= 1280 ? 400 : 360,
          child: const ColoredBox(
            color: Colors.transparent,
            child: OrderCart(),
          ),
        ),
      ],
    );
  }
}

class _CatalogPane extends ConsumerWidget {
  const _CatalogPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: AppSpacing.page(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _OrderContextBar(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = AppSearchBar(
                hintText: 'Cari nama produk atau SKU',
                onChanged: ref.read(catalogProvider.notifier).search,
                onClear: () => ref.read(catalogProvider.notifier).search(''),
              );
              final manualItemButton = OutlinedButton.icon(
                onPressed: () => _showManualItem(context, ref),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Item manual'),
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 8),
                    SizedBox(height: 44, child: manualItemButton),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  SizedBox(height: 48, child: manualItemButton),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const CategoryChips(),
          const Expanded(child: ProductGrid()),
        ],
      ),
    );
  }

  Future<void> _showManualItem(BuildContext context, WidgetRef ref) async {
    final draft = await AppBottomSheet.show<_ManualItemDraft>(
      context,
      title: 'Tambah item manual',
      child: const _ManualItemForm(),
    );
    if (draft == null || !context.mounted) return;

    ref
        .read(cartProvider.notifier)
        .addManualItem(
          draft.description,
          draft.price,
          quantity: draft.quantity,
        );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Item manual ditambahkan.')));
  }
}

class _ManualItemForm extends StatefulWidget {
  const _ManualItemForm();

  @override
  State<_ManualItemForm> createState() => _ManualItemFormState();
}

class _ManualItemFormState extends State<_ManualItemForm> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _price = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _description,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Deskripsi item',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              validator: (value) {
                final description = (value ?? '').trim();
                if (description.isEmpty) return 'Deskripsi wajib diisi';
                if (description.length < 3) {
                  return 'Deskripsi minimal 3 karakter';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Harga satuan',
                prefixText: 'Rp ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final price = double.tryParse(value ?? '');
                if (price == null || price <= 0) {
                  return 'Harga wajib lebih dari 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            Text('Jumlah', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Kurangi jumlah',
                  onPressed: _quantity == 1
                      ? null
                      : () => setState(() => _quantity--),
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Tambah jumlah',
                  onPressed: _quantity == 99
                      ? null
                      : () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Tambahkan ke pesanan',
              icon: Icons.add_shopping_cart_rounded,
              onPressed: _submit,
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
      _ManualItemDraft(
        description: _description.text.trim(),
        price: double.parse(_price.text),
        quantity: _quantity,
      ),
    );
  }
}

class _ManualItemDraft {
  const _ManualItemDraft({
    required this.description,
    required this.price,
    required this.quantity,
  });

  final String description;
  final double price;
  final int quantity;
}

class _OrderContextBar extends ConsumerWidget {
  const _OrderContextBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final customerName = cart.customerName?.trim();
    final hasCustomer = customerName != null && customerName.isNotEmpty;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pesanan baru', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              hasCustomer ? Icons.person_rounded : Icons.person_outline_rounded,
              size: 18,
              color: hasCustomer
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hasCustomer ? customerName : 'Pelanggan umum',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (hasCustomer
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                          color: hasCustomer
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: hasCustomer
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
              ),
            ),
          ],
        ),
      ],
    );
    final typeButton = OutlinedButton.icon(
      onPressed: () => _showOrderType(context, ref),
      icon: Icon(_iconForType(cart.orderType), size: 19),
      label: Text(cart.orderTypeLabel, overflow: TextOverflow.ellipsis),
    );
    final tableButton = OutlinedButton.icon(
      onPressed: () => context.push('/tables'),
      icon: const Icon(Icons.table_restaurant_outlined, size: 19),
      label: Text(
        cart.tableName ?? 'Pilih meja',
        overflow: TextOverflow.ellipsis,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 540) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: typeButton),
                  if (cart.orderType == 'dine_in') ...[
                    const SizedBox(width: 8),
                    Expanded(child: tableButton),
                  ],
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 8),
            typeButton,
            if (cart.orderType == 'dine_in') ...[
              const SizedBox(width: 8),
              tableButton,
            ],
          ],
        );
      },
    );
  }

  IconData _iconForType(String type) => switch (type) {
    'dine_in' => Icons.restaurant_outlined,
    'delivery' => Icons.delivery_dining_outlined,
    _ => Icons.takeout_dining_outlined,
  };

  Future<void> _showOrderType(BuildContext context, WidgetRef ref) {
    final selected = ref.read(cartProvider).orderType;
    return AppBottomSheet.show<void>(
      context,
      title: 'Tipe pesanan',
      subtitle: 'Pilih sesuai cara pesanan disajikan.',
      child: Builder(
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OrderTypeTile(
                title: 'Makan di tempat',
                subtitle: 'Gunakan meja dan kirim ke dapur.',
                icon: Icons.restaurant_outlined,
                selected: selected == 'dine_in',
                onTap: () {
                  ref.read(cartProvider.notifier).setOrderType('dine_in');
                  Navigator.pop(sheetContext);
                  context.push('/tables');
                },
              ),
              _OrderTypeTile(
                title: 'Bawa pulang',
                subtitle: 'Pesanan dikemas untuk dibawa.',
                icon: Icons.takeout_dining_outlined,
                selected: selected == 'take_away',
                onTap: () {
                  ref.read(cartProvider.notifier).setOrderType('take_away');
                  Navigator.pop(sheetContext);
                },
              ),
              _OrderTypeTile(
                title: 'Pesan antar',
                subtitle: 'Pesanan untuk kurir atau pengantaran.',
                icon: Icons.delivery_dining_outlined,
                selected: selected == 'delivery',
                onTap: () {
                  ref.read(cartProvider.notifier).setOrderType('delivery');
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTypeTile extends StatelessWidget {
  const _OrderTypeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: 72,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, color: selected ? theme.colorScheme.secondary : null),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.secondary)
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
