import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_list_tile.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../kds/providers/kds_provider.dart';
import '../../pos/providers/table_provider.dart';
import '../../../core/router/role_navigation.dart';

class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(kdsNotifierProvider).value ?? [];
    final tableState = ref.watch(tableProvider).value;
    final inventory = ref.watch(inventoryProvider).value;
    final user = ref.watch(authProvider).user;
    final activeTickets = tickets
        .where((ticket) => ticket.status != 'completed')
        .length;
    final occupiedTables =
        tableState?.tables
            .where((table) => table.status == 'occupied')
            .length ??
        0;
    final lowStock =
        inventory?.items.where((item) => item.isLowStock).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operasional outlet'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () {
              ref.invalidate(kdsNotifierProvider);
              ref.read(tableProvider.notifier).refresh();
              ref.read(inventoryProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.page(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 760 ? 3 : 2;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: width,
                          height: 112,
                          child: AppMetricCard(
                            title: 'Tiket produksi',
                            value: '$activeTickets',
                            icon: Icons.soup_kitchen_outlined,
                            iconColor: activeTickets == 0
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          height: 112,
                          child: AppMetricCard(
                            title: 'Meja terisi',
                            value: '$occupiedTables',
                            icon: Icons.table_restaurant_outlined,
                            iconColor: AppColors.info,
                          ),
                        ),
                        if (columns == 3)
                          SizedBox(
                            width: width,
                            height: 112,
                            child: AppMetricCard(
                              title: 'Stok menipis',
                              value: '$lowStock',
                              icon: Icons.inventory_2_outlined,
                              iconColor: lowStock == 0
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Layanan outlet',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListTile(
                        title: 'Absensi saya',
                        subtitle:
                            'Catat masuk atau pulang dengan foto dan lokasi',
                        icon: Icons.fingerprint_rounded,
                        onTap: () => context.push('/attendance'),
                      ),
                      if (canManageAttendanceForUser(user)) ...[
                        const Divider(),
                        AppListTile(
                          title: 'Manajemen absensi',
                          subtitle:
                              'Laporan, jadwal, keterlambatan, dan koreksi',
                          icon: Icons.fact_check_outlined,
                          onTap: () => context.push('/attendance/manage'),
                        ),
                      ],
                      const Divider(),
                      if (canManageProductsForUser(user)) ...[
                        AppListTile(
                          title: 'Kelola produk',
                          subtitle: 'Katalog, harga, dan stasiun produksi',
                          icon: Icons.restaurant_menu_rounded,
                          onTap: () => context.push('/products/manage'),
                        ),
                        const Divider(),
                        AppListTile(
                          title: 'Kelola kategori',
                          subtitle: 'Kelompok dan urutan katalog POS',
                          icon: Icons.category_outlined,
                          onTap: () => context.push('/categories/manage'),
                        ),
                        const Divider(),
                      ],
                      AppListTile(
                        title: 'Meja & area',
                        subtitle: '$occupiedTables meja sedang digunakan',
                        icon: Icons.table_restaurant_outlined,
                        onTap: () => context.push('/table-management'),
                      ),
                      const Divider(),
                      AppListTile(
                        title: 'Dapur & bar',
                        subtitle: '$activeTickets tiket masih aktif',
                        icon: Icons.soup_kitchen_outlined,
                        onTap: () => context.go('/kds'),
                      ),
                      const Divider(),
                      AppListTile(
                        title: 'Laporan shift',
                        subtitle: 'Rekonsiliasi transaksi perangkat',
                        icon: Icons.receipt_long_outlined,
                        onTap: () => context.push('/shift-report'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Persediaan & menu',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListTile(
                        title: 'Persediaan',
                        subtitle: '$lowStock item perlu diperiksa',
                        icon: Icons.inventory_2_outlined,
                        onTap: () => context.go('/inventory'),
                      ),
                      const Divider(),
                      AppListTile(
                        title: 'Resep & HPP',
                        subtitle: 'Komposisi dan biaya menu',
                        icon: Icons.menu_book_outlined,
                        onTap: () => context.push('/recipes'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
