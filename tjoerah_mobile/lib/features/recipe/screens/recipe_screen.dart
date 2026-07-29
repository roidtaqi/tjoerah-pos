import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/role_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/csv_transfer_service.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/recipe_models.dart';
import '../providers/recipe_provider.dart';

class RecipeScreen extends ConsumerStatefulWidget {
  const RecipeScreen({super.key});

  @override
  ConsumerState<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends ConsumerState<RecipeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';
  String? _selectedRecipeId;
  bool _isMutating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (!canManageCatalogForUser(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Resep & HPP')),
        body: const AppErrorState(
          title: 'Akses dibatasi',
          message: 'Hanya owner atau admin yang dapat mengelola resep.',
        ),
      );
    }

    final recipes = ref.watch(recipeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resep & HPP'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang resep',
            onPressed: _isMutating
                ? null
                : () => ref.read(recipeProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isMutating
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: recipes.when(
        loading: () =>
            const AppLoadingState(message: 'Menghitung biaya resep...'),
        error: (_, _) => AppErrorState(
          message: 'Data resep belum dapat dibaca.',
          onRetry: () => ref.read(recipeProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    setState(() => _isMutating = true);
    try {
      final bytes = await ref.read(recipeProvider.notifier).downloadTemplate();
      await CsvTransferService.share(
        bytes: bytes,
        filename: 'template-resep.csv',
        subject: 'Template impor resep Tjoerah POS',
      );
    } catch (_) {
      if (mounted) {
        _showResult(
          const RecipeMutationResult.failure(
            'Template resep belum dapat diunduh.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _importTemplate() async {
    final file = await CsvTransferService.pick();
    if (file == null || !mounted) return;
    setState(() => _isMutating = true);
    final result = await ref
        .read(recipeProvider.notifier)
        .importRecipes(bytes: file.bytes, filename: file.name);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Widget _buildContent(List<RecipeModel> recipes) {
    final query = _query.trim().toLowerCase();
    final visibleRecipes = recipes.where((recipe) {
      final matchesStatus = _status == 'all' || recipe.status == _status;
      final matchesQuery =
          query.isEmpty ||
          recipe.name.toLowerCase().contains(query) ||
          (recipe.productName?.toLowerCase().contains(query) ?? false);
      return matchesStatus && matchesQuery;
    }).toList();
    final averageCost = recipes.isEmpty
        ? 0.0
        : recipes.fold<double>(0, (sum, recipe) => sum + recipe.currentCost) /
              recipes.length;
    final incomplete = recipes.where((recipe) => recipe.items.isEmpty).length;
    final activeCount = recipes
        .where((recipe) => recipe.status == 'active')
        .length;
    final selected =
        visibleRecipes
            .where((recipe) => recipe.id == _selectedRecipeId)
            .firstOrNull ??
        visibleRecipes.firstOrNull;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: AppSpacing.page(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isMutating
                          ? null
                          : () => context.go('/inventory'),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Persediaan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isMutating ? null : _downloadTemplate,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Unduh template'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isMutating ? null : _importTemplate,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Impor CSV'),
                    ),
                    FilledButton.icon(
                      onPressed: _isMutating ? null : _openRecipeForm,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah resep'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (MediaQuery.sizeOf(context).width >= 760) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 24) / 3;
                      return Row(
                        children: [
                          SizedBox(
                            width: width,
                            height: 112,
                            child: AppMetricCard(
                              title: 'Total resep',
                              value: '${recipes.length}',
                              icon: Icons.menu_book_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: width,
                            height: 112,
                            child: AppMetricCard(
                              title: 'Rata-rata HPP',
                              value: _currency().format(averageCost),
                              icon: Icons.calculate_outlined,
                              iconColor: AppColors.info,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: width,
                            height: 112,
                            child: AppMetricCard(
                              title: 'Perlu dilengkapi',
                              value: '$incomplete',
                              icon: Icons.rule_rounded,
                              iconColor: incomplete > 0
                                  ? AppColors.warning
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: AppSearchBar(
                        controller: _searchController,
                        hintText: 'Cari resep atau produk',
                        onChanged: (value) => setState(() => _query = value),
                        onClear: () => setState(() => _query = ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${visibleRecipes.length} resep',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'all',
                        label: Text('Semua ${recipes.length}'),
                      ),
                      ButtonSegment(
                        value: 'active',
                        label: Text('Aktif $activeCount'),
                      ),
                      ButtonSegment(
                        value: 'draft',
                        label: Text(
                          'Draft ${recipes.where((recipe) => recipe.status == 'draft').length}',
                        ),
                      ),
                      ButtonSegment(
                        value: 'inactive',
                        label: Text(
                          'Nonaktif ${recipes.where((recipe) => recipe.status == 'inactive').length}',
                        ),
                      ),
                    ],
                    selected: {_status},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        setState(() => _status = selection.first),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: visibleRecipes.isEmpty
                      ? AppEmptyState(
                          title: recipes.isEmpty
                              ? 'Belum ada resep'
                              : 'Resep tidak ditemukan',
                          message: recipes.isEmpty
                              ? 'Buat resep pertama dari bahan persediaan untuk mulai menghitung HPP.'
                              : 'Coba kata kunci atau status yang berbeda.',
                          icon: recipes.isEmpty
                              ? Icons.menu_book_outlined
                              : Icons.search_off_rounded,
                          onAction: recipes.isEmpty ? null : _clearFilters,
                          actionLabel: recipes.isEmpty ? null : 'Hapus filter',
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth >= 860) {
                              return Row(
                                children: [
                                  SizedBox(
                                    width: 350,
                                    child: _RecipeList(
                                      recipes: visibleRecipes,
                                      selectedId: selected?.id,
                                      onSelected: (recipe) {
                                        setState(
                                          () => _selectedRecipeId = recipe.id,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: selected == null
                                        ? const SizedBox.shrink()
                                        : _RecipeDetail(
                                            recipe: selected,
                                            enabled: !_isMutating,
                                            onEdit: () => _openRecipeForm(
                                              recipe: selected,
                                            ),
                                            onDuplicate: () => _openRecipeForm(
                                              recipe: selected,
                                              duplicate: true,
                                            ),
                                            onToggle: () =>
                                                _toggleRecipe(selected),
                                            onDelete: () =>
                                                _confirmDelete(selected),
                                          ),
                                  ),
                                ],
                              );
                            }
                            return _RecipeList(
                              recipes: visibleRecipes,
                              onSelected: _showRecipeDetails,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _status = 'all';
    });
  }

  Future<void> _showRecipeDetails(RecipeModel recipe) {
    Future<void> closeThen(Future<void> Function() action) async {
      Navigator.pop(context);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (mounted) await action();
    }

    return AppBottomSheet.show<void>(
      context,
      title: recipe.name,
      subtitle: 'HPP ${_currency().format(recipe.currentCost)}',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: _RecipeDetail(
          recipe: recipe,
          enabled: !_isMutating,
          onEdit: () => closeThen(() => _openRecipeForm(recipe: recipe)),
          onDuplicate: () =>
              closeThen(() => _openRecipeForm(recipe: recipe, duplicate: true)),
          onToggle: () => closeThen(() => _toggleRecipe(recipe)),
          onDelete: () => closeThen(() => _confirmDelete(recipe)),
        ),
      ),
    );
  }

  Future<void> _openRecipeForm({
    RecipeModel? recipe,
    bool duplicate = false,
  }) async {
    setState(() => _isMutating = true);
    RecipeEditorOptions options;
    try {
      options = await ref.read(recipeProvider.notifier).loadEditorOptions();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isMutating = false);
      _showMessage(
        'Produk dan bahan belum dapat dimuat. Periksa koneksi lalu coba lagi.',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isMutating = false);

    if (options.ingredients.where((item) => item.isActive).isEmpty) {
      _showMessage(
        'Tambahkan bahan aktif di Persediaan sebelum membuat resep.',
        error: true,
        actionLabel: 'Buka Persediaan',
        onAction: () => context.go('/inventory'),
      );
      return;
    }

    final recipes = ref.read(recipeProvider).asData?.value ?? const [];
    final unavailableProducts = recipes
        .where((item) => item.id != recipe?.id)
        .map((item) => item.productId)
        .whereType<String>()
        .toSet();
    final initial = recipe == null
        ? null
        : RecipeDraft.fromRecipe(recipe, duplicate: duplicate);
    final draft = await AppBottomSheet.show<RecipeDraft>(
      context,
      title: recipe == null
          ? 'Resep baru'
          : duplicate
          ? 'Duplikat resep'
          : 'Edit resep',
      subtitle: 'HPP dihitung dari biaya rata-rata bahan persediaan',
      child: _RecipeForm(
        initial: initial,
        options: options,
        unavailableProductIds: unavailableProducts,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _isMutating = true);
    final notifier = ref.read(recipeProvider.notifier);
    final result = recipe == null || duplicate
        ? await notifier.createRecipe(draft)
        : await notifier.updateRecipe(recipe, draft);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _toggleRecipe(RecipeModel recipe) async {
    final newStatus = recipe.status == 'active' ? 'inactive' : 'active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          newStatus == 'active' ? 'Aktifkan resep?' : 'Nonaktifkan resep?',
        ),
        content: Text(
          newStatus == 'active'
              ? '${recipe.name} akan digunakan sebagai komposisi produksi aktif.'
              : '${recipe.name} tetap tersimpan, tetapi ditandai tidak aktif.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(newStatus == 'active' ? 'Aktifkan' : 'Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMutating = true);
    final source = RecipeDraft.fromRecipe(recipe);
    final draft = RecipeDraft(
      name: source.name,
      productId: source.productId,
      status: newStatus,
      yieldQuantity: source.yieldQuantity,
      yieldUnit: source.yieldUnit,
      items: source.items,
    );
    final result = await ref
        .read(recipeProvider.notifier)
        .updateRecipe(recipe, draft);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _confirmDelete(RecipeModel recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus resep?'),
        content: Text(
          '${recipe.name} akan dihapus dari pengelolaan resep. Versi dan transaksi lama tetap tersimpan untuk audit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Hapus'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMutating = true);
    final result = await ref.read(recipeProvider.notifier).deleteRecipe(recipe);
    if (!mounted) return;
    setState(() {
      _isMutating = false;
      if (_selectedRecipeId == recipe.id) _selectedRecipeId = null;
    });
    _showResult(result);
  }

  void _showResult(RecipeMutationResult result) {
    _showMessage(result.message, error: !result.isSuccess);
  }

  void _showMessage(
    String message, {
    bool error = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }
}

class _RecipeList extends StatelessWidget {
  const _RecipeList({
    required this.recipes,
    required this.onSelected,
    this.selectedId,
  });

  final List<RecipeModel> recipes;
  final ValueChanged<RecipeModel> onSelected;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 84),
        itemCount: recipes.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final recipe = recipes[index];
          final selected = selectedId == recipe.id;
          return Material(
            color: selected
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            child: ListTile(
              minTileHeight: 82,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 5,
              ),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 21,
                ),
              ),
              title: Text(
                recipe.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    recipe.productName ?? 'Tanpa produk terkait',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  AppBadge(
                    text: _statusLabel(recipe.status),
                    color: _statusColor(recipe.status),
                    textColor: _statusTextColor(recipe.status),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currency().format(recipe.currentCost),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'v${recipe.activeVersion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              onTap: () => onSelected(recipe),
            ),
          );
        },
      ),
    );
  }
}

class _RecipeDetail extends StatelessWidget {
  const _RecipeDetail({
    required this.recipe,
    required this.enabled,
    required this.onEdit,
    required this.onDuplicate,
    required this.onToggle,
    required this.onDelete,
  });

  final RecipeModel recipe;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recipe.productName ?? 'Tanpa produk terkait',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit resep',
                  onPressed: enabled ? onEdit : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Aksi resep',
                  enabled: enabled,
                  onSelected: (value) {
                    if (value == 'duplicate') onDuplicate();
                    if (value == 'toggle') onToggle();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.copy_outlined),
                        title: Text('Duplikat'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          recipe.status == 'active'
                              ? Icons.pause_circle_outline_rounded
                              : Icons.play_circle_outline_rounded,
                        ),
                        title: Text(
                          recipe.status == 'active'
                              ? 'Nonaktifkan'
                              : 'Aktifkan',
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Hapus'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppBadge(
                  text: _statusLabel(recipe.status),
                  color: _statusColor(recipe.status),
                  textColor: _statusTextColor(recipe.status),
                ),
                AppBadge(
                  text: 'Versi ${recipe.activeVersion}',
                  icon: Icons.history_rounded,
                ),
                AppBadge(
                  text:
                      'Hasil ${_compactNumber(recipe.yieldQuantity)} ${recipe.yieldUnit ?? 'porsi'}',
                  icon: Icons.scale_outlined,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _CostValue(
                      label: 'Total satu batch',
                      value: _currency().format(recipe.totalBatchCost),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CostValue(
                      label: 'HPP per ${recipe.yieldUnit ?? 'porsi'}',
                      value: _currency().format(recipe.currentCost),
                      emphasized: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
            child: Text('Komposisi bahan', style: theme.textTheme.titleMedium),
          ),
          if (recipe.items.isEmpty)
            const SizedBox(
              height: 180,
              child: AppEmptyState(
                title: 'Komposisi belum lengkap',
                message: 'Edit resep untuk menambahkan bahan.',
                icon: Icons.rule_rounded,
              ),
            )
          else
            ...recipe.items.map(
              (item) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text(
                  item.inventoryItemName ??
                      'Bahan #${item.inventoryItemId ?? '-'}',
                  style: theme.textTheme.titleMedium,
                ),
                subtitle: Text(
                  '${_currency().format(item.unitCost)}/${item.unit ?? 'unit'} - Susut ${_compactNumber(item.wastePercent)}%',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_compactNumber(item.quantity)} ${item.unit ?? ''}',
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(
                      _currency().format(item.totalCost),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          if (recipe.versions.isNotEmpty) ...[
            const Divider(height: 28),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 18),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              leading: const Icon(Icons.history_rounded),
              title: const Text('Riwayat versi'),
              subtitle: Text('${recipe.versions.length} versi tersimpan'),
              children: recipe.versions
                  .map(
                    (version) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Versi ${version.version}'),
                      subtitle: Text(
                        version.effectiveAt == null
                            ? _statusLabel(version.status)
                            : '${_statusLabel(version.status)} - ${DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(version.effectiveAt!.toLocal())}',
                      ),
                      trailing: Text(
                        _currency().format(version.totalCost),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CostValue extends StatelessWidget {
  const _CostValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: emphasized
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _RecipeForm extends StatefulWidget {
  const _RecipeForm({
    required this.initial,
    required this.options,
    required this.unavailableProductIds,
  });

  final RecipeDraft? initial;
  final RecipeEditorOptions options;
  final Set<String> unavailableProductIds;

  @override
  State<_RecipeForm> createState() => _RecipeFormState();
}

class _RecipeFormState extends State<_RecipeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _yieldQuantity;
  late final TextEditingController _yieldUnit;
  late String _status;
  String? _productId;
  final List<_IngredientEditor> _ingredients = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name);
    _yieldQuantity = TextEditingController(
      text: initial == null ? '1' : _compactNumber(initial.yieldQuantity),
    );
    _yieldUnit = TextEditingController(text: initial?.yieldUnit ?? 'porsi');
    _status = initial?.status ?? 'draft';
    _productId = initial?.productId;
    for (final item in initial?.items ?? const <RecipeIngredientDraft>[]) {
      final option = widget.options.ingredients
          .where((candidate) => candidate.id == item.inventoryItemId)
          .firstOrNull;
      if (option != null) {
        _ingredients.add(
          _IngredientEditor(
            option: option,
            quantity: item.quantity,
            wastePercent: item.wastePercent,
            onChanged: _refreshCost,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _yieldQuantity.dispose();
    _yieldUnit.dispose();
    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.78, 760.0);
    final products = widget.options.products
        .where(
          (product) =>
              !widget.unavailableProductIds.contains(product.id) &&
              (product.isActive || product.id == _productId),
        )
        .toList();

    return SizedBox(
      height: height,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama resep',
                      prefixIcon: Icon(Icons.menu_book_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Nama resep wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue:
                        products.any((product) => product.id == _productId)
                        ? _productId
                        : '_none',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Produk POS',
                      prefixIcon: Icon(Icons.restaurant_menu_rounded),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '_none',
                        child: Text('Tanpa produk terkait'),
                      ),
                      ...products.map(
                        (product) => DropdownMenuItem<String>(
                          value: product.id,
                          child: Text(
                            product.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _productId = value == '_none' ? null : value,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final quantity = TextFormField(
                        controller: _yieldQuantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [_decimalFormatter],
                        decoration: const InputDecoration(
                          labelText: 'Jumlah hasil',
                          prefixIcon: Icon(Icons.scale_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _positiveNumberValidator,
                      );
                      final unit = TextFormField(
                        controller: _yieldUnit,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Satuan hasil',
                          hintText: 'porsi, cup, loyang',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Satuan wajib diisi'
                            : null,
                      );
                      if (constraints.maxWidth < 440) {
                        return Column(
                          children: [
                            quantity,
                            const SizedBox(height: 14),
                            unit,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: quantity),
                          const SizedBox(width: 12),
                          Expanded(child: unit),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Status resep',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'draft',
                          icon: Icon(Icons.edit_note_rounded),
                          label: Text('Draft'),
                        ),
                        ButtonSegment(
                          value: 'active',
                          icon: Icon(Icons.check_circle_outline_rounded),
                          label: Text('Aktif'),
                        ),
                        ButtonSegment(
                          value: 'inactive',
                          icon: Icon(Icons.pause_circle_outline_rounded),
                          label: Text('Nonaktif'),
                        ),
                      ],
                      selected: {_status},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          setState(() => _status = selection.first),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bahan resep',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addIngredient,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Tambah bahan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_ingredients.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tambahkan setidaknya satu bahan untuk menghitung HPP.',
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(
                      _ingredients.length,
                      (index) => Padding(
                        padding: EdgeInsets.only(
                          bottom: index == _ingredients.length - 1 ? 0 : 10,
                        ),
                        child: _IngredientEditorRow(
                          editor: _ingredients[index],
                          options: widget.options.ingredients,
                          selectedIds: _ingredients
                              .map((editor) => editor.option.id)
                              .toSet(),
                          onOptionChanged: (option) {
                            setState(() => _ingredients[index].option = option);
                          },
                          onRemove: () => _removeIngredient(index),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  _LiveCostSummary(
                    batchCost: _batchCost,
                    costPerYield: _costPerYield,
                    yieldUnit: _yieldUnit.text.trim().isEmpty
                        ? 'hasil'
                        : _yieldUnit.text.trim(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: AppButton(
                text: widget.initial == null
                    ? 'Simpan resep'
                    : 'Simpan sebagai versi baru',
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _batchCost => _ingredients.fold<double>(
    0,
    (sum, editor) =>
        sum +
        editor.quantity *
            editor.option.unitCost *
            (1 + (editor.wastePercent / 100)),
  );

  double get _costPerYield {
    final yield = _parseDecimal(_yieldQuantity.text);
    return yield > 0 ? _batchCost / yield : 0;
  }

  void _refreshCost() {
    if (mounted) setState(() {});
  }

  void _addIngredient() {
    final selected = _ingredients.map((editor) => editor.option.id).toSet();
    final available = widget.options.ingredients
        .where((option) => option.isActive && !selected.contains(option.id))
        .firstOrNull;
    if (available == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua bahan aktif sudah ditambahkan.')),
      );
      return;
    }
    setState(() {
      _ingredients.add(
        _IngredientEditor(option: available, onChanged: _refreshCost),
      );
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredients.removeAt(index).dispose();
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan setidaknya satu bahan.')),
      );
      return;
    }

    Navigator.pop(
      context,
      RecipeDraft(
        name: _name.text,
        productId: _productId,
        status: _status,
        yieldQuantity: _parseDecimal(_yieldQuantity.text),
        yieldUnit: _yieldUnit.text,
        items: _ingredients
            .map(
              (editor) => RecipeIngredientDraft(
                inventoryItemId: editor.option.id,
                quantity: editor.quantity,
                wastePercent: editor.wastePercent,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _IngredientEditorRow extends StatelessWidget {
  const _IngredientEditorRow({
    required this.editor,
    required this.options,
    required this.selectedIds,
    required this.onOptionChanged,
    required this.onRemove,
  });

  final _IngredientEditor editor;
  final List<RecipeIngredientOption> options;
  final Set<String> selectedIds;
  final ValueChanged<RecipeIngredientOption> onOptionChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final allowedOptions = options
        .where(
          (option) =>
              option.id == editor.option.id ||
              (option.isActive && !selectedIds.contains(option.id)),
        )
        .toList();
    final ingredient = DropdownButtonFormField<String>(
      initialValue: editor.option.id,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Bahan'),
      items: allowedOptions
          .map(
            (option) => DropdownMenuItem(
              value: option.id,
              child: Text(option.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (id) {
        final option = options
            .where((candidate) => candidate.id == id)
            .firstOrNull;
        if (option != null) onOptionChanged(option);
      },
    );
    final quantity = TextFormField(
      controller: editor.quantityController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_decimalFormatter],
      decoration: InputDecoration(
        labelText: 'Jumlah',
        suffixText: editor.option.unit,
      ),
      validator: _positiveNumberValidator,
    );
    final waste = TextFormField(
      controller: editor.wasteController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_decimalFormatter],
      decoration: const InputDecoration(labelText: 'Susut', suffixText: '%'),
      validator: (value) {
        final amount = _parseDecimal(value ?? '');
        return amount < 0 || amount > 100 ? '0-100' : null;
      },
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final total = _currency().format(
            editor.quantity *
                editor.option.unitCost *
                (1 + (editor.wastePercent / 100)),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: ingredient),
                    IconButton(
                      tooltip: 'Hapus bahan',
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: quantity),
                    const SizedBox(width: 10),
                    Expanded(child: waste),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$total per batch',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: ingredient),
                  const SizedBox(width: 10),
                  Expanded(child: quantity),
                  const SizedBox(width: 10),
                  Expanded(child: waste),
                  IconButton(
                    tooltip: 'Hapus bahan',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_currency().format(editor.option.unitCost)}/${editor.option.unit}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '$total per batch',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveCostSummary extends StatelessWidget {
  const _LiveCostSummary({
    required this.batchCost,
    required this.costPerYield,
    required this.yieldUnit,
  });

  final double batchCost;
  final double costPerYield;
  final String yieldUnit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: _CostValue(
              label: 'Total batch',
              value: _currency().format(batchCost),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _CostValue(
              label: 'HPP per $yieldUnit',
              value: _currency().format(costPerYield),
              emphasized: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientEditor {
  _IngredientEditor({
    required this.option,
    double quantity = 1,
    double wastePercent = 0,
    required this.onChanged,
  }) : quantityController = TextEditingController(
         text: _compactNumber(quantity),
       ),
       wasteController = TextEditingController(
         text: _compactNumber(wastePercent),
       ) {
    quantityController.addListener(onChanged);
    wasteController.addListener(onChanged);
  }

  RecipeIngredientOption option;
  final TextEditingController quantityController;
  final TextEditingController wasteController;
  final VoidCallback onChanged;

  double get quantity => _parseDecimal(quantityController.text);
  double get wastePercent => _parseDecimal(wasteController.text);

  void dispose() {
    quantityController.removeListener(onChanged);
    wasteController.removeListener(onChanged);
    quantityController.dispose();
    wasteController.dispose();
  }
}

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

String? _positiveNumberValidator(String? value) {
  return _parseDecimal(value ?? '') <= 0 ? 'Harus lebih dari 0' : null;
}

double _parseDecimal(String value) {
  return double.tryParse(value.replaceAll(',', '.')) ?? 0;
}

String _compactNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

String _statusLabel(String status) => switch (status) {
  'active' => 'Aktif',
  'inactive' => 'Nonaktif',
  _ => 'Draft',
};

Color _statusColor(String status) => switch (status) {
  'active' => AppColors.successSoft,
  'inactive' => AppColors.surfaceMuted,
  _ => AppColors.warningSoft,
};

Color _statusTextColor(String status) => switch (status) {
  'active' => AppColors.success,
  'inactive' => AppColors.textSecondary,
  _ => AppColors.warning,
};

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
