import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
import '../models/inventory_models.dart';
import '../providers/inventory_provider.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final items = inventory.value?.items ?? const <InventoryItemModel>[];
    final showTextActions = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventori'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Stok saat ini'),
            Tab(text: 'Riwayat pergerakan'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang inventori',
            onPressed: () => ref.read(inventoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (showTextActions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () => context.push('/recipes'),
                icon: const Icon(Icons.menu_book_outlined, size: 19),
                label: const Text('Resep'),
              ),
            ),
          const SizedBox(width: 8),
          if (showTextActions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton.icon(
                onPressed: items.isEmpty
                    ? null
                    : () => _showIncidentSheet(items),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Catat stok'),
              ),
            )
          else
            IconButton.filled(
              tooltip: 'Catat perubahan stok',
              onPressed: items.isEmpty ? null : () => _showIncidentSheet(items),
              icon: const Icon(Icons.add_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: inventory.when(
        loading: () =>
            const AppLoadingState(message: 'Menghitung saldo stok...'),
        error: (error, _) => AppErrorState(
          message: 'Inventori lokal belum dapat dibaca.',
          onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
        ),
        data: (state) => TabBarView(
          controller: _tabController,
          children: [
            _buildStockTab(state.items),
            _buildMovementsTab(state.movements),
          ],
        ),
      ),
    );
  }

  Widget _buildStockTab(List<InventoryItemModel> items) {
    final query = _query.trim().toLowerCase();
    final visibleItems = items.where((item) {
      final matchesQuery =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.sku.toLowerCase().contains(query);
      return matchesQuery && (!_lowStockOnly || item.isLowStock);
    }).toList();
    final lowStockCount = items.where((item) => item.isLowStock).length;
    final inventoryValue = items.fold<double>(
      0,
      (sum, item) => sum + item.currentStock * item.weightedAverageCost,
    );
    final currency = _currency();

    return SafeArea(
      child: Padding(
        padding: AppSpacing.page(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth >= 800
                    ? (constraints.maxWidth - 24) / 3
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      height: 116,
                      child: AppMetricCard(
                        title: 'Item aktif',
                        value: '${items.length}',
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      height: 116,
                      child: AppMetricCard(
                        title: 'Stok menipis',
                        value: '$lowStockCount',
                        icon: Icons.warning_amber_rounded,
                        iconColor: lowStockCount > 0
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ),
                    if (constraints.maxWidth >= 800)
                      SizedBox(
                        width: itemWidth,
                        height: 116,
                        child: AppMetricCard(
                          title: 'Nilai persediaan',
                          value: currency.format(inventoryValue),
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: AppColors.info,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppSearchBar(
                    controller: _searchController,
                    hintText: 'Cari nama item atau SKU',
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () => setState(() => _query = ''),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Stok menipis'),
                  selected: _lowStockOnly,
                  onSelected: (value) => setState(() => _lowStockOnly = value),
                  avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: visibleItems.isEmpty
                  ? AppEmptyState(
                      title: items.isEmpty
                          ? 'Belum ada item inventori'
                          : 'Item tidak ditemukan',
                      message: items.isEmpty
                          ? 'Sinkronkan data outlet untuk melihat saldo stok.'
                          : 'Coba kata kunci atau filter lain.',
                      icon: items.isEmpty
                          ? Icons.inventory_2_outlined
                          : Icons.search_off_rounded,
                    )
                  : _InventoryTable(items: visibleItems),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementsTab(List<StockMovementModel> movements) {
    return SafeArea(
      child: Padding(
        padding: AppSpacing.page(context),
        child: movements.isEmpty
            ? const AppEmptyState(
                title: 'Belum ada pergerakan stok',
                message:
                    'Penerimaan, penyesuaian, dan pemakaian akan muncul di sini.',
                icon: Icons.swap_vert_rounded,
              )
            : AppCard(
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  itemCount: movements.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) =>
                      _MovementRow(movement: movements[index]),
                ),
              ),
      ),
    );
  }

  Future<void> _showIncidentSheet(List<InventoryItemModel> items) async {
    var selectedItem = items.first;
    var selectedType = 'spoilage';
    var submitting = false;
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await AppBottomSheet.show<void>(
      context,
      title: 'Catat perubahan stok',
      subtitle: 'Perubahan disimpan lokal dan masuk antrean sinkronisasi.',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventoryItemModel>(
                  initialValue: selectedItem,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Item inventori',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  items: items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (item) {
                    if (item != null) setSheetState(() => selectedItem = item);
                  },
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: 'spoilage',
                      icon: Icon(Icons.delete_outline_rounded),
                      label: Text('Terbuang'),
                    ),
                    ButtonSegment(
                      value: 'adjustment',
                      icon: Icon(Icons.add_rounded),
                      label: Text('Tambah stok'),
                    ),
                  ],
                  selected: {selectedType},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setSheetState(() => selectedType = selection.first);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Jumlah',
                    suffixText: selectedItem.unit,
                    prefixIcon: const Icon(Icons.numbers_rounded),
                  ),
                  validator: (value) {
                    final quantity = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return quantity == null || quantity <= 0
                        ? 'Masukkan jumlah lebih dari 0'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: reasonController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Alasan',
                    hintText: 'Contoh: rusak saat penerimaan',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Alasan wajib diisi'
                      : null,
                ),
                const SizedBox(height: 18),
                AppButton(
                  text: 'Simpan perubahan',
                  icon: Icons.check_rounded,
                  isLoading: submitting,
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setSheetState(() => submitting = true);
                    final quantity = double.parse(
                      quantityController.text.replaceAll(',', '.'),
                    );
                    final success = await ref
                        .read(inventoryProvider.notifier)
                        .adjustStock(
                          itemId: selectedItem.id,
                          qty: quantity,
                          reason: reasonController.text.trim(),
                          type: selectedType,
                        );
                    if (!mounted || !sheetContext.mounted) return;
                    if (success) {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Perubahan stok berhasil disimpan.'),
                        ),
                      );
                    } else {
                      setSheetState(() => submitting = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    quantityController.dispose();
    reasonController.dispose();
  }
}

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({required this.items});

  final List<InventoryItemModel> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (wide)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Row(
                children: [
                  Expanded(flex: 4, child: Text('ITEM')),
                  Expanded(flex: 2, child: Text('SKU')),
                  Expanded(flex: 2, child: Text('BIAYA')),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('SALDO'),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) =>
                  _InventoryRow(item: items[index], wide: wide),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item, required this.wide});

  final InventoryItemModel item;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockColor = item.isLowStock
        ? AppColors.error
        : theme.colorScheme.onSurface;
    final cost = _currency().format(item.weightedAverageCost);
    final stock = '${item.currentStock.toStringAsFixed(1)} ${item.unit}';

    if (wide) {
      return SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Icon(
                      item.isLowStock
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_outlined,
                      size: 20,
                      color: item.isLowStock
                          ? AppColors.warning
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(flex: 2, child: Text(item.sku.isEmpty ? '-' : item.sku)),
              Expanded(flex: 2, child: Text(cost)),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    stock,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: stockColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListTile(
      minTileHeight: 76,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Icon(
        item.isLowStock
            ? Icons.warning_amber_rounded
            : Icons.inventory_2_outlined,
        color: item.isLowStock
            ? AppColors.warning
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (item.isLowStock)
            const AppBadge(
              text: 'Menipis',
              color: Color(0xFFFEF3C7),
              textColor: AppColors.warning,
            ),
        ],
      ),
      subtitle: Text(
        '${item.sku.isEmpty ? 'Tanpa SKU' : item.sku} - $cost/${item.unit}',
      ),
      trailing: Text(
        stock,
        style: theme.textTheme.titleMedium?.copyWith(color: stockColor),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final StockMovementModel movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = movement.quantity >= 0;
    final color = positive ? AppColors.success : AppColors.error;
    final date = DateTime.tryParse(movement.date);
    final dateLabel = date == null
        ? movement.date
        : AppDateFormatter.shortDateTime(date.toLocal());

    return ListTile(
      minTileHeight: 76,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          positive ? Icons.south_west_rounded : Icons.north_east_rounded,
          color: color,
          size: 20,
        ),
      ),
      title: Text(movement.itemName, style: theme.textTheme.titleMedium),
      subtitle: Text('${_movementLabel(movement.type)} - $dateLabel'),
      trailing: Text(
        '${positive ? '+' : ''}${movement.quantity.toStringAsFixed(1)}',
        style: theme.textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }
}

String _movementLabel(String type) => switch (type) {
  'purchase' => 'Penerimaan',
  'sale' => 'Pemakaian',
  'spoilage' || 'wastage' => 'Terbuang',
  'transfer' => 'Transfer',
  _ => 'Penyesuaian',
};

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
