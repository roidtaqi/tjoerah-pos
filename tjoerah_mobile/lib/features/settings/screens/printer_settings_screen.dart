import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/printer/printer_device.dart';
import '../../../core/printer/printer_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../providers/printer_provider.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  PrinterDestination _selectedDestination = PrinterDestination.cashier;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printerProvider);
    final notifier = ref.read(printerProvider.notifier);
    final profile = state.profile(_selectedDestination);
    final busy = state.isPrinting || state.isScanning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Bluetooth'),
        actions: [
          IconButton(
            tooltip: 'Buka pengaturan Bluetooth',
            onPressed: busy ? null : notifier.openBluetoothSettings,
            icon: const Icon(Icons.settings_bluetooth_rounded),
          ),
          IconButton(
            tooltip: 'Muat printer yang dipasangkan',
            onPressed: busy ? null : notifier.scanDevices,
            icon: state.isScanning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.page(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BluetoothSummary(state: state),
                  const SizedBox(height: 16),
                  SegmentedButton<PrinterDestination>(
                    expandedInsets: EdgeInsets.zero,
                    segments: PrinterDestination.values
                        .map(
                          (destination) => ButtonSegment(
                            value: destination,
                            icon: Icon(_destinationIcon(destination)),
                            label: Text(destination.shortLabel),
                          ),
                        )
                        .toList(),
                    selected: {_selectedDestination},
                    showSelectedIcon: false,
                    onSelectionChanged: busy
                        ? null
                        : (selection) => setState(
                            () => _selectedDestination = selection.first,
                          ),
                  ),
                  const SizedBox(height: 12),
                  _PrinterProfilePanel(
                    state: state,
                    profile: profile,
                    onChooseDevice: () => _chooseDevice(state, profile),
                    onWidthChanged: (width) =>
                        notifier.setPaperWidth(profile.destination, width),
                    onCopiesChanged: (copies) =>
                        notifier.setCopies(profile.destination, copies),
                    onAutoPrintChanged: (value) =>
                        notifier.setAutoPrint(profile.destination, value),
                    onCutPaperChanged: (value) =>
                        notifier.setCutPaper(profile.destination, value),
                    onTest: () => notifier.testPrint(profile.destination),
                    onClear: () => notifier.clearDevice(profile.destination),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDevice(PrinterState state, PrinterProfile profile) async {
    final devicesByAddress = <String, PrinterDevice>{
      for (final device in state.devices)
        if (normalizePrinterAddress(device.identifier).isNotEmpty)
          normalizePrinterAddress(device.identifier): PrinterDevice(
            name: device.name,
            identifier: normalizePrinterAddress(device.identifier),
          ),
    };
    if (profile.isConfigured &&
        !devicesByAddress.containsKey(
          normalizePrinterAddress(profile.deviceAddress),
        )) {
      devicesByAddress[normalizePrinterAddress(
        profile.deviceAddress,
      )] = PrinterDevice(
        name: profile.deviceName ?? 'Printer Bluetooth',
        identifier: normalizePrinterAddress(profile.deviceAddress),
      );
    }
    final devices = devicesByAddress.values.toList()
      ..sort((left, right) {
        final byName = _deviceName(
          left,
        ).toLowerCase().compareTo(_deviceName(right).toLowerCase());
        return byName != 0
            ? byName
            : _deviceAddress(left).compareTo(_deviceAddress(right));
      });

    final selected = await AppBottomSheet.show<PrinterDevice>(
      context,
      title: 'Pilih printer ${profile.destination.shortLabel.toLowerCase()}',
      subtitle: '${devices.length} perangkat Bluetooth tersedia',
      child: devices.isEmpty
          ? AppEmptyState(
              title: 'Belum ada printer',
              message:
                  'Aktifkan printer Bluetooth, lalu muat ulang daftar perangkat.',
              icon: Icons.bluetooth_disabled_rounded,
              actionLabel: 'Buka Bluetooth',
              onAction: () {
                Navigator.pop(context);
                ref.read(printerProvider.notifier).openBluetoothSettings();
              },
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.58,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: devices.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (sheetContext, index) {
                  final device = devices[index];
                  final address = _deviceAddress(device);
                  final assigned = state.profiles.entries
                      .where(
                        (entry) =>
                            entry.value.isConfigured &&
                            normalizePrinterAddress(
                                  entry.value.deviceAddress,
                                ) ==
                                address,
                      )
                      .map((entry) => entry.key.shortLabel)
                      .join(', ');
                  final isSelected =
                      normalizePrinterAddress(profile.deviceAddress) == address;

                  return ListTile(
                    minTileHeight: 76,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.print_outlined, size: 21),
                    ),
                    title: Text(
                      _deviceName(device),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      assigned.isEmpty
                          ? 'ID $address'
                          : 'ID $address\nDigunakan: $assigned',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(sheetContext).colorScheme.primary,
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(sheetContext, device),
                  );
                },
              ),
            ),
    );

    if (selected != null && mounted) {
      await ref
          .read(printerProvider.notifier)
          .assignDevice(profile.destination, selected);
    }
  }
}

class _BluetoothSummary extends StatelessWidget {
  const _BluetoothSummary({required this.state});

  final PrinterState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = state.profiles.values
        .where((profile) => profile.isConfigured)
        .length;
    final statusColor = state.error != null
        ? theme.colorScheme.error
        : state.notice != null
        ? AppColors.success
        : theme.colorScheme.onSurfaceVariant;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bluetooth_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${state.devices.length} perangkat ditemukan',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  state.error ??
                      state.notice ??
                      '$configured dari 3 profil printer telah diatur',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppBadge(
            text: '$configured/3',
            color: configured > 0
                ? AppColors.successSoft
                : theme.colorScheme.surfaceContainerHighest,
            textColor: configured > 0
                ? AppColors.success
                : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _PrinterProfilePanel extends StatelessWidget {
  const _PrinterProfilePanel({
    required this.state,
    required this.profile,
    required this.onChooseDevice,
    required this.onWidthChanged,
    required this.onCopiesChanged,
    required this.onAutoPrintChanged,
    required this.onCutPaperChanged,
    required this.onTest,
    required this.onClear,
  });

  final PrinterState state;
  final PrinterProfile profile;
  final VoidCallback onChooseDevice;
  final ValueChanged<PrinterPaperWidth> onWidthChanged;
  final ValueChanged<int> onCopiesChanged;
  final ValueChanged<bool> onAutoPrintChanged;
  final ValueChanged<bool> onCutPaperChanged;
  final VoidCallback onTest;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = state.isPrinting || state.isScanning;
    final active = state.activeDestination == profile.destination;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.destination.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.destination.description,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(
                text: active
                    ? 'Mencetak'
                    : profile.isConfigured
                    ? 'Siap'
                    : 'Belum diatur',
                color: active || profile.isConfigured
                    ? AppColors.successSoft
                    : theme.colorScheme.surfaceContainerHighest,
                textColor: active || profile.isConfigured
                    ? AppColors.success
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: theme.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.colorScheme.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy ? null : onChooseDevice,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    const Icon(Icons.print_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.deviceName ?? 'Pilih printer Bluetooth',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.isConfigured
                                ? 'ID ${profile.deviceAddress!.toUpperCase()}'
                                : 'Belum ada perangkat yang dipilih',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.unfold_more_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Lebar kertas', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<PrinterPaperWidth>(
            expandedInsets: EdgeInsets.zero,
            segments: PrinterPaperWidth.values
                .map(
                  (width) =>
                      ButtonSegment(value: width, label: Text(width.label)),
                )
                .toList(),
            selected: {profile.paperWidth},
            showSelectedIcon: false,
            onSelectionChanged: busy
                ? null
                : (selection) => onWidthChanged(selection.first),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Jumlah salinan',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton.outlined(
                tooltip: 'Kurangi salinan',
                onPressed: busy || profile.copies <= 1
                    ? null
                    : () => onCopiesChanged(profile.copies - 1),
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${profile.copies}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton.outlined(
                tooltip: 'Tambah salinan',
                onPressed: busy || profile.copies >= 3
                    ? null
                    : () => onCopiesChanged(profile.copies + 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cetak otomatis'),
            subtitle: const Text('Jalankan setelah pembayaran berhasil'),
            value: profile.autoPrint,
            onChanged: busy ? null : onAutoPrintChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Potong kertas'),
            subtitle: const Text('Untuk printer dengan auto-cutter'),
            value: profile.cutPaper,
            onChanged: busy ? null : onCutPaperChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: !profile.isConfigured || busy ? null : onTest,
                  icon: active
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: const Text('Cetak tes'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Hapus printer dari profil',
                onPressed: !profile.isConfigured || busy ? null : onClear,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _deviceName(PrinterDevice device) {
  final name = device.name.trim();
  return name.isEmpty ? 'Printer tanpa nama' : name;
}

String _deviceAddress(PrinterDevice device) {
  final address = normalizePrinterAddress(device.identifier);
  return address.isEmpty ? 'ID tidak tersedia' : address;
}

IconData _destinationIcon(PrinterDestination destination) =>
    switch (destination) {
      PrinterDestination.cashier => Icons.point_of_sale_outlined,
      PrinterDestination.kitchen => Icons.restaurant_outlined,
      PrinterDestination.bar => Icons.local_cafe_outlined,
    };
