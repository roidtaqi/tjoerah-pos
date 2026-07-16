import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_page_header.dart';
import '../providers/cart_provider.dart';

class OrderTypeScreen extends ConsumerWidget {
  const OrderTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = [
      const _OrderTypeOption(
        value: 'dine_in',
        title: 'Makan di tempat',
        description: 'Pilih meja lalu kirim pesanan ke dapur.',
        icon: Icons.restaurant_outlined,
      ),
      const _OrderTypeOption(
        value: 'take_away',
        title: 'Bawa pulang',
        description: 'Siapkan pesanan dalam kemasan.',
        icon: Icons.takeout_dining_outlined,
      ),
      const _OrderTypeOption(
        value: 'delivery',
        title: 'Pesan antar',
        description: 'Tandai pesanan untuk kurir atau pengantaran.',
        icon: Icons.delivery_dining_outlined,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan baru')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: AppSpacing.page(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppPageHeader(
                    title: 'Pilih tipe pesanan',
                    subtitle:
                        'Pilihan ini dapat diubah kembali dari layar kasir.',
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 720 ? 3 : 1;
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: columns == 1 ? 132 : 232,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            return _OrderTypeCard(
                              option: option,
                              onTap: () {
                                ref
                                    .read(cartProvider.notifier)
                                    .setOrderType(option.value);
                                context.go(
                                  option.value == 'dine_in'
                                      ? '/tables'
                                      : '/pos',
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderTypeCard extends StatelessWidget {
  const _OrderTypeCard({required this.option, required this.onTap});

  final _OrderTypeOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxHeight < 170;
          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(option.icon, color: theme.colorScheme.secondary),
          );
          final copy = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(option.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(option.description, style: theme.textTheme.bodySmall),
            ],
          );

          if (horizontal) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 16),
                Expanded(child: copy),
                const Icon(Icons.chevron_right_rounded),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [icon, const Spacer(), copy],
          );
        },
      ),
    );
  }
}

class _OrderTypeOption {
  const _OrderTypeOption({
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String value;
  final String title;
  final String description;
  final IconData icon;
}
