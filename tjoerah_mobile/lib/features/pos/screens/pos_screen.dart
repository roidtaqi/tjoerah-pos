import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_search_bar.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
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
}

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
          AppSearchBar(
            hintText: 'Cari nama produk atau SKU',
            onChanged: ref.read(catalogProvider.notifier).search,
            onClear: () => ref.read(catalogProvider.notifier).search(''),
          ),
          const SizedBox(height: 12),
          const CategoryChips(),
          const Expanded(child: ProductGrid()),
        ],
      ),
    );
  }
}

class _OrderContextBar extends ConsumerWidget {
  const _OrderContextBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pesanan baru', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          cart.customerName ?? 'Pelanggan umum',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
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
