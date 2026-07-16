import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../models/table_models.dart';
import '../providers/cart_provider.dart';
import '../providers/table_provider.dart';

class TableSelectionScreen extends ConsumerStatefulWidget {
  const TableSelectionScreen({super.key});

  @override
  ConsumerState<TableSelectionScreen> createState() =>
      _TableSelectionScreenState();
}

class _TableSelectionScreenState extends ConsumerState<TableSelectionScreen> {
  String _filter = 'all';
  String? _selectingTableId;

  @override
  Widget build(BuildContext context) {
    final tableState = ref.watch(tableProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih meja'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang meja',
            onPressed: () => ref.read(tableProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: tableState.when(
        loading: () =>
            const AppLoadingState(message: 'Menyiapkan denah meja...'),
        error: (error, _) => AppErrorState(
          message: 'Data meja lokal belum dapat dibaca.',
          onRetry: () => ref.read(tableProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(TableState state) {
    if (state.floors.isEmpty) {
      return const AppEmptyState(
        title: 'Belum ada area meja',
        message: 'Tambahkan lantai dan meja dari pengaturan outlet.',
        icon: Icons.table_restaurant_outlined,
      );
    }

    final currentTables = state.tables.where((table) {
      final inFloor = table.floorId == state.selectedFloorId;
      final matchesFilter = _filter == 'all' || table.status == _filter;
      return inFloor && matchesFilter;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: AppSpacing.page(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.floors.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final floor = state.floors[index];
                  return ChoiceChip(
                    label: Text(floor.name),
                    selected: state.selectedFloorId == floor.id,
                    showCheckmark: false,
                    onSelected: (_) =>
                        ref.read(tableProvider.notifier).selectFloor(floor.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('Semua')),
                        ButtonSegment(
                          value: 'available',
                          label: Text('Tersedia'),
                        ),
                        ButtonSegment(value: 'occupied', label: Text('Terisi')),
                        ButtonSegment(
                          value: 'cleaning',
                          label: Text('Dibersihkan'),
                        ),
                      ],
                      selected: {_filter},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _filter = selection.first);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${currentTables.length} meja',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: currentTables.isEmpty
                  ? const AppEmptyState(
                      title: 'Tidak ada meja',
                      message: 'Ubah filter untuk melihat meja lainnya.',
                      icon: Icons.filter_alt_off_outlined,
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            mainAxisExtent: 138,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: currentTables.length,
                      itemBuilder: (context, index) {
                        final table = currentTables[index];
                        return _TableCard(
                          table: table,
                          isLoading: _selectingTableId == table.id,
                          onTap: () => _selectTable(table),
                          onMore: table.status == 'occupied'
                              ? () => _showTableActions(table, state.tables)
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            const _StatusLegend(),
          ],
        ),
      ),
    );
  }

  Future<void> _selectTable(DiningTableModel table) async {
    if (table.status == 'cleaning') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meja masih dalam proses dibersihkan.')),
      );
      return;
    }

    setState(() => _selectingTableId = table.id);
    try {
      if (table.status == 'available') {
        await ref.read(tableProvider.notifier).openSession(table.id);
      }
      ref.read(cartProvider.notifier)
        ..setOrderType('dine_in')
        ..setTable(table.id, name: table.name);
      if (mounted) context.go('/pos');
    } finally {
      if (mounted) setState(() => _selectingTableId = null);
    }
  }

  Future<void> _showTableActions(
    DiningTableModel source,
    List<DiningTableModel> allTables,
  ) {
    final targets = allTables
        .where((table) => table.id != source.id && table.status == 'occupied')
        .toList();

    return AppBottomSheet.show<void>(
      context,
      title: source.name,
      subtitle: '${source.capacity} kursi - Sedang digunakan',
      child: Builder(
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                minTileHeight: 60,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Buka pesanan meja'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _selectTable(source);
                },
              ),
              if (targets.isNotEmpty)
                ListTile(
                  minTileHeight: 60,
                  leading: const Icon(Icons.merge_type_rounded),
                  title: const Text('Gabungkan meja'),
                  subtitle: const Text('Pilih meja tujuan'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showMergeTargets(source, targets);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMergeTargets(
    DiningTableModel source,
    List<DiningTableModel> targets,
  ) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Gabungkan ${source.name}',
      subtitle: 'Pesanan akan dipindahkan ke meja tujuan.',
      child: Builder(
        builder: (sheetContext) => ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          itemCount: targets.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final target = targets[index];
            return ListTile(
              minTileHeight: 60,
              leading: const Icon(Icons.table_restaurant_outlined),
              title: Text(target.name),
              subtitle: Text('${target.capacity} kursi'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await ref
                    .read(tableProvider.notifier)
                    .mergeTable(source.id, target.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            );
          },
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.isLoading,
    required this.onTap,
    this.onMore,
  });

  final DiningTableModel table;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(table.status);
    final label = _statusLabel(table.status);

    return Semantics(
      button: table.status != 'cleaning',
      label: '${table.name}, ${table.capacity} kursi, $label',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.table_restaurant_outlined,
                      color: color,
                      size: 22,
                    ),
                    const Spacer(),
                    if (isLoading)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (onMore != null)
                      InkWell(
                        onTap: onMore,
                        borderRadius: BorderRadius.circular(6),
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Icons.more_horiz_rounded),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  table.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${table.capacity} kursi',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendItem(label: 'Tersedia', color: AppColors.success),
        _LegendItem(label: 'Terisi', color: AppColors.error),
        _LegendItem(label: 'Dibersihkan', color: AppColors.warning),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

Color _statusColor(String status) => switch (status) {
  'occupied' => AppColors.error,
  'cleaning' => AppColors.warning,
  _ => AppColors.success,
};

String _statusLabel(String status) => switch (status) {
  'occupied' => 'Terisi',
  'cleaning' => 'Dibersihkan',
  _ => 'Tersedia',
};
