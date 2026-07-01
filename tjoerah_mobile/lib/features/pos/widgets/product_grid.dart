import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_empty_state.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';

class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();

    if (catalog.isLoading) {
      return const AppLoadingState(message: 'Loading products...');
    }

    final products = catalog.filteredProducts;

    if (products.isEmpty) {
      return const AppEmptyState(
        title: 'No Products',
        message: 'No products found. Try syncing your catalog.',
        icon: Icons.coffee,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return InkWell(
          onTap: () {
            context.read<CartProvider>().addItem(
              product.id,
              product.name,
              product.price,
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                    ),
                    child: const Icon(Icons.coffee, size: 48, color: AppColors.textSecondary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rp ${product.price.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
