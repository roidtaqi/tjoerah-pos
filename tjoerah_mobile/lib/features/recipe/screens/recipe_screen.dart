import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
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
  String? _selectedRecipeId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resep & HPP'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang resep',
            onPressed: () => ref.read(recipeProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: recipes.when(
        loading: () =>
            const AppLoadingState(message: 'Menghitung biaya resep...'),
        error: (error, _) => AppErrorState(
          message: 'Data resep lokal belum dapat dibaca.',
          onRetry: () => ref.read(recipeProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<RecipeModel> recipes) {
    if (recipes.isEmpty) {
      return const AppEmptyState(
        title: 'Belum ada resep',
        message:
            'Sinkronkan katalog pusat untuk memuat komposisi dan biaya resep.',
        icon: Icons.menu_book_outlined,
      );
    }

    final query = _query.trim().toLowerCase();
    final visibleRecipes = recipes
        .where((recipe) => recipe.name.toLowerCase().contains(query))
        .toList();
    final totalCost = recipes.fold<double>(
      0,
      (sum, recipe) => sum + recipe.currentCost,
    );
    final incomplete = recipes.where((recipe) => recipe.items.isEmpty).length;
    final selected =
        visibleRecipes
            .where((recipe) => recipe.id == _selectedRecipeId)
            .firstOrNull ??
        visibleRecipes.firstOrNull;

    return SafeArea(
      child: Padding(
        padding: AppSpacing.page(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          value: _currency().format(totalCost / recipes.length),
                          icon: Icons.calculate_outlined,
                          iconColor: AppColors.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: width,
                        height: 112,
                        child: AppMetricCard(
                          title: 'Belum lengkap',
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
            AppSearchBar(
              controller: _searchController,
              hintText: 'Cari resep atau produk',
              onChanged: (value) => setState(() => _query = value),
              onClear: () => setState(() => _query = ''),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: visibleRecipes.isEmpty
                  ? const AppEmptyState(
                      title: 'Resep tidak ditemukan',
                      message: 'Coba kata kunci lain.',
                      icon: Icons.search_off_rounded,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 860) {
                          return Row(
                            children: [
                              SizedBox(
                                width: 340,
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
                                        onEdit: _editIngredient,
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
    );
  }

  Future<void> _showRecipeDetails(RecipeModel recipe) {
    return AppBottomSheet.show<void>(
      context,
      title: recipe.name,
      subtitle: 'HPP ${_currency().format(recipe.currentCost)}',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: _RecipeDetail(recipe: recipe, onEdit: _editIngredient),
      ),
    );
  }

  Future<void> _editIngredient(RecipeModel recipe, RecipeItemModel item) async {
    final quantityController = TextEditingController(
      text: item.quantity.toString(),
    );
    final wasteController = TextEditingController(
      text: item.wastePercent.toString(),
    );
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await AppBottomSheet.show<void>(
      context,
      title: item.inventoryItemName ?? 'Ubah bahan',
      subtitle: recipe.name,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Jumlah per resep',
                    suffixText: item.unit,
                    prefixIcon: const Icon(Icons.scale_outlined),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return amount == null || amount <= 0
                        ? 'Masukkan jumlah lebih dari 0'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: wasteController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Susut bahan',
                    suffixText: '%',
                    prefixIcon: Icon(Icons.percent_rounded),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return amount == null || amount < 0 || amount > 100
                        ? 'Gunakan nilai antara 0 dan 100'
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                AppButton(
                  text: 'Simpan perubahan',
                  icon: Icons.check_rounded,
                  isLoading: saving,
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setSheetState(() => saving = true);
                    await ref
                        .read(recipeProvider.notifier)
                        .updateRecipeItem(
                          recipeId: recipe.id,
                          itemId: item.id,
                          newQty: double.parse(
                            quantityController.text.replaceAll(',', '.'),
                          ),
                          wastePercent: double.parse(
                            wasteController.text.replaceAll(',', '.'),
                          ),
                        );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    quantityController.dispose();
    wasteController.dispose();
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
              minTileHeight: 76,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              leading: Container(
                width: 40,
                height: 40,
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
              subtitle: Text(
                '${recipe.items.length} bahan - Hasil ${recipe.yieldQuantity.toStringAsFixed(1)} ${recipe.yieldUnit ?? ''}',
              ),
              trailing: Text(
                _currency().format(recipe.currentCost),
                style: Theme.of(context).textTheme.labelLarge,
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
  const _RecipeDetail({required this.recipe, required this.onEdit});

  final RecipeModel recipe;
  final void Function(RecipeModel recipe, RecipeItemModel item) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        recipe.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppBadge(
                      text: 'HPP ${_currency().format(recipe.currentCost)}',
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Hasil ${recipe.yieldQuantity.toStringAsFixed(1)} ${recipe.yieldUnit ?? 'porsi'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Divider(color: theme.colorScheme.outline),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Text('Komposisi bahan', style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: recipe.items.isEmpty
                ? const AppEmptyState(
                    title: 'Komposisi belum lengkap',
                    message:
                        'Tambahkan bahan dari panel pengelolaan resep pusat.',
                    icon: Icons.rule_rounded,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    itemCount: recipe.items.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = recipe.items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.inventoryItemName ??
                              'Bahan #${item.inventoryItemId ?? '-'}',
                          style: theme.textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          '${_currency().format(item.unitCost)}/${item.unit ?? 'unit'} - Susut ${item.wastePercent.toStringAsFixed(1)}%',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${item.quantity.toStringAsFixed(2)} ${item.unit ?? ''}',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Ubah bahan',
                              onPressed: () => onEdit(recipe, item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
