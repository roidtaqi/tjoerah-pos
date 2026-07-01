import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/components/app_search_bar.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../repositories/order_repository.dart';
import '../widgets/category_chips.dart';
import '../widgets/product_grid.dart';
import '../widgets/floating_cart.dart';
import '../../../core/theme/app_colors.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => CatalogProvider()),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tjoerah POS', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Sync Catalog',
                onPressed: () async {
                  final catalog = context.read<CatalogProvider>();
                  await catalog.syncFromServer();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Catalog synced!')),
                    );
                  }
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {},
            ),
          ],
        ),
        body: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppSearchBar(
                hintText: 'Search products by name or SKU...',
                onChanged: (val) {},
              ),
            ),
            const CategoryChips(),
            const Expanded(
              child: ProductGrid(),
            ),
            const SizedBox(height: 80),
          ],
        ),
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: FloatingCartPanel(),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: AppSearchBar(
                  hintText: 'Search products...',
                  onChanged: (val) {},
                ),
              ),
              const CategoryChips(),
              const Expanded(
                child: ProductGrid(),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          flex: 1,
          child: Builder(
            builder: (context) {
              final cart = context.watch<CartProvider>();
              return _buildTabletCartSidebar(context, cart);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleCheckout(BuildContext context, CartProvider cart) async {
    final repo = OrderRepository();
    try {
      final orderId = await repo.createOrder(
        items: cart.items,
        subtotal: cart.subtotal,
        tax: cart.tax,
        total: cart.total,
      );
      cart.clearCart();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order #${orderId.substring(0, 8)} created!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildTabletCartSidebar(BuildContext context, CartProvider cart) {
    if (cart.itemCount == 0) {
      return const Center(
        child: Text('Cart is empty', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Current Order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: cart.items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = cart.items[index];
              return ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Rp ${item.price.toStringAsFixed(0)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => cart.updateQuantity(item.productId, item.quantity - 1),
                    ),
                    Text('${item.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => cart.updateQuantity(item.productId, item.quantity + 1),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal', style: TextStyle(color: AppColors.textSecondary)),
                  Text('Rp ${cart.subtotal.toStringAsFixed(0)}'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tax (11%)', style: TextStyle(color: AppColors.textSecondary)),
                  Text('Rp ${cart.tax.toStringAsFixed(0)}'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Rp ${cart.total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleCheckout(context, cart),
                  child: const Text('Charge'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => cart.clearCart(),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Void Order'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
