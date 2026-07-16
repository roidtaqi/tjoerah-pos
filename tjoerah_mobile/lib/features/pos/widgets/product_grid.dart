import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../models/product_model.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogState = ref.watch(catalogProvider);

    return catalogState.when(
      loading: () => const AppLoadingState(message: 'Menyiapkan katalog...'),
      error: (error, _) => AppErrorState(
        message:
            'Katalog tersimpan tetap aman. Coba muat ulang saat koneksi tersedia.',
        onRetry: () => ref.read(catalogProvider.notifier).reload(),
      ),
      data: (catalog) {
        final products = catalog.filteredProducts;
        if (products.isEmpty) {
          final searching = catalog.searchQuery.trim().isNotEmpty;
          return AppEmptyState(
            title: searching
                ? 'Produk tidak ditemukan'
                : 'Katalog masih kosong',
            message: searching
                ? 'Coba kata kunci atau kategori lain.'
                : 'Sinkronkan katalog untuk mulai menerima pesanan.',
            icon: searching
                ? Icons.search_off_rounded
                : Icons.menu_book_rounded,
            onAction: searching
                ? () => ref.read(catalogProvider.notifier).search('')
                : () => ref.read(catalogProvider.notifier).syncFromServer(),
            actionLabel: searching ? 'Hapus pencarian' : 'Sinkronkan katalog',
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 112),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            mainAxisExtent: 156,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) =>
              _ProductTile(product: products[index]),
        );
      },
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final quantity = ref.watch(
      cartProvider.select(
        (cart) => cart.items
            .where((item) => item.productId == product.id)
            .fold(0, (sum, item) => sum + item.quantity),
      ),
    );

    return Semantics(
      button: true,
      label: '${product.name}, ${currency.format(product.price)}',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: quantity > 0
                ? theme.colorScheme.secondary
                : theme.colorScheme.outline,
            width: quantity > 0 ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref
              .read(cartProvider.notifier)
              .addItem(
                product.id,
                product.name,
                product.price,
                station: product.station,
              ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _iconForStation(product.station),
                        size: 22,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const Spacer(),
                    if (quantity > 0)
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$quantity',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    else
                      Icon(
                        Icons.add_circle_outline_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  currency.format(product.price),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForStation(String? station) {
    return switch (station) {
      'bar' => Icons.local_cafe_outlined,
      'kitchen' => Icons.restaurant_outlined,
      _ => Icons.fastfood_outlined,
    };
  }
}
