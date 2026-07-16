import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/router/role_navigation.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_list_tile.dart';
import '../providers/printer_provider.dart';
import '../providers/sync_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final sync = ref.watch(syncProvider);
    final printer = ref.watch(printerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final role = appRoleForUser(auth.user);

    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: SingleChildScrollView(
        padding: AppSpacing.page(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHeader(user: auth.user),
                const SizedBox(height: 24),
                const _SectionLabel(
                  title: 'Operasional',
                  subtitle: 'Akses cepat ke pengelolaan outlet',
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (role == AppRole.production)
                        AppListTile(
                          title: 'Dapur & bar',
                          subtitle: 'Kembali ke antrean produksi',
                          icon: Icons.soup_kitchen_outlined,
                          onTap: () => context.go('/kds'),
                        )
                      else ...[
                        AppListTile(
                          title: 'Meja & area',
                          subtitle: role == AppRole.cashier
                              ? 'Pilih meja untuk transaksi dine-in'
                              : 'Susun area, kapasitas, dan status meja',
                          icon: Icons.table_restaurant_outlined,
                          onTap: () => context.push(
                            role == AppRole.cashier
                                ? '/tables'
                                : '/table-management',
                          ),
                        ),
                        if (role != AppRole.cashier) ...[
                          const Divider(),
                          AppListTile(
                            title: 'Resep & HPP',
                            subtitle: 'Komposisi, susut, dan biaya produk',
                            icon: Icons.menu_book_outlined,
                            onTap: () => context.push('/recipes'),
                          ),
                        ],
                        const Divider(),
                        AppListTile(
                          title: 'Laporan shift',
                          subtitle: 'Rekonsiliasi transaksi perangkat',
                          icon: Icons.receipt_long_outlined,
                          onTap: () => context.push('/shift-report'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionLabel(
                  title: 'Tampilan',
                  subtitle: 'Sesuaikan dengan kondisi kerja outlet',
                ),
                const SizedBox(height: 10),
                AppCard(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.contrast_rounded, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mode warna',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Terang, gelap, atau mengikuti perangkat',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            tooltip: 'Terang',
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.settings_brightness_outlined),
                            tooltip: 'Sistem',
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            tooltip: 'Gelap',
                          ),
                        ],
                        selected: {themeMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) => ref
                            .read(themeModeProvider.notifier)
                            .setThemeMode(selection.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionLabel(
                  title: 'Sinkronisasi',
                  subtitle: 'Status data offline dan antrean pengiriman',
                ),
                const SizedBox(height: 10),
                _SyncCard(
                  state: sync,
                  onSync: () => ref.read(syncProvider.notifier).forceSync(),
                ),
                const SizedBox(height: 24),
                const _SectionLabel(
                  title: 'Printer struk',
                  subtitle: 'Perangkat Bluetooth yang sudah dipasangkan',
                ),
                const SizedBox(height: 10),
                _PrinterCard(
                  state: printer,
                  onRefresh: () =>
                      ref.read(printerProvider.notifier).scanDevices(),
                  onConnect: (device) =>
                      ref.read(printerProvider.notifier).connect(device),
                  onDisconnect: () =>
                      ref.read(printerProvider.notifier).disconnect(),
                  onTest: () => ref.read(printerProvider.notifier).testPrint(),
                ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Keluar dari akun',
                  icon: Icons.logout_rounded,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => _logout(context, ref),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tjoerah POS - Versi 1.0.0',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Data transaksi yang belum tersinkron tetap tersimpan di perangkat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final Map<String, dynamic>? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user?['name']?.toString() ?? 'Admin Kasir';
    final role = roleLabel(appRoleForUser(user));
    final outlets = user?['outlets'];
    final firstOutlet = outlets is List && outlets.isNotEmpty
        ? outlets.first
        : null;
    final outlet =
        user?['outlet_name']?.toString() ??
        (firstOutlet is Map ? firstOutlet['name']?.toString() : null) ??
        'Tjoerah Coffee - Outlet Utama';
    final initial = name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase();

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            initial,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                outlet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppBadge(text: role, icon: Icons.badge_outlined),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.state, required this.onSync});

  final SyncState state;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = state.pendingCount > 0;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (pending ? AppColors.warning : AppColors.success)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: state.isSyncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    pending
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined,
                    color: pending ? AppColors.warning : AppColors.success,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isSyncing
                      ? 'Menyinkronkan data'
                      : pending
                      ? '${state.pendingCount} data menunggu'
                      : 'Semua data tersinkron',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  state.error != null
                      ? state.error!
                      : pending
                      ? 'Data akan dikirim otomatis saat koneksi tersedia.'
                      : state.lastSyncedAt == null
                      ? 'Perangkat siap digunakan secara offline.'
                      : 'Sinkron terakhir ${_syncTime(state.lastSyncedAt!)}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: state.error == null ? null : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: 'Sinkronkan sekarang',
            onPressed: state.isSyncing ? null : onSync,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
    );
  }

  String _syncTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({
    required this.state,
    required this.onRefresh,
    required this.onConnect,
    required this.onDisconnect,
    required this.onTest,
  });

  final PrinterState state;
  final VoidCallback onRefresh;
  final ValueChanged<dynamic> onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.connectedDevice == null
                        ? 'Belum ada printer terhubung'
                        : state.connectedDevice!.name ?? 'Printer Bluetooth',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (state.connectedDevice != null)
                  const AppBadge(
                    text: 'Terhubung',
                    color: Color(0xFFDCFCE7),
                    textColor: AppColors.success,
                  ),
                IconButton(
                  tooltip: 'Cari ulang perangkat',
                  onPressed: state.isScanning ? null : onRefresh,
                  icon: state.isScanning
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Bluetooth belum tersedia di perangkat ini.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Divider(color: theme.colorScheme.outline),
          if (state.connectedDevice != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTest,
                      icon: const Icon(Icons.print_outlined, size: 19),
                      label: const Text('Cetak tes'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.link_off_rounded, size: 19),
                      label: const Text('Putuskan'),
                    ),
                  ),
                ],
              ),
            )
          else if (!state.isScanning && state.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Tidak ada printer yang sudah dipasangkan. Pasangkan printer dari pengaturan perangkat, lalu cari ulang.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            ...state.devices.map(
              (device) => ListTile(
                minTileHeight: 64,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.bluetooth_rounded),
                title: Text(device.name ?? 'Printer tanpa nama'),
                subtitle: Text(device.address ?? ''),
                trailing: FilledButton.tonal(
                  onPressed: state.isConnecting
                      ? null
                      : () => onConnect(device),
                  child: const Text('Hubungkan'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
