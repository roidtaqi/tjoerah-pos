import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/role_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_search_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pos/models/category_model.dart';
import '../providers/product_management_provider.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';
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
        appBar: AppBar(title: const Text('Kelola kategori')),
        body: const AppErrorState(
          title: 'Akses dibatasi',
          message: 'Hanya owner atau admin yang dapat mengelola kategori.',
        ),
      );
    }

    final catalog = ref.watch(productManagementProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola kategori'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang kategori',
            onPressed: _isMutating
                ? null
                : () => ref.read(productManagementProvider.notifier).refresh(),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isMutating ? null : () => _openCategoryForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah kategori'),
      ),
      body: catalog.when(
        loading: () => const AppLoadingState(message: 'Memuat kategori...'),
        error: (_, _) => AppErrorState(
          message: 'Kategori belum dapat dimuat dari server.',
          onRetry: () => ref.read(productManagementProvider.notifier).refresh(),
        ),
        data: _buildCatalog,
      ),
    );
  }

  Widget _buildCatalog(ProductManagementState state) {
    final byId = {
      for (final category in state.categories) category.id: category,
    };
    final query = _query.trim().toLowerCase();
    final ordered = _orderedCategories(state.categories);
    final categories = ordered.where((category) {
      final matchesStatus =
          _status == 'all' ||
          (_status == 'active' && category.isActive) ||
          (_status == 'inactive' && !category.isActive);
      final parentName = byId[category.parentId]?.name.toLowerCase() ?? '';
      final matchesQuery =
          query.isEmpty ||
          category.name.toLowerCase().contains(query) ||
          parentName.contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
    final activeCount = state.categories
        .where((category) => category.isActive)
        .length;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: AppSpacing.page(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.isFromCache) ...[
                  _CategoryOfflineNotice(
                    onRefresh: () =>
                        ref.read(productManagementProvider.notifier).refresh(),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: AppSearchBar(
                        controller: _searchController,
                        hintText: 'Cari kategori atau induk',
                        onChanged: (value) => setState(() => _query = value),
                        onClear: () => setState(() => _query = ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${categories.length} kategori',
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
                        label: Text('Semua ${state.categories.length}'),
                      ),
                      ButtonSegment(
                        value: 'active',
                        label: Text('Aktif $activeCount'),
                      ),
                      ButtonSegment(
                        value: 'inactive',
                        label: Text(
                          'Nonaktif ${state.categories.length - activeCount}',
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
                  child: categories.isEmpty
                      ? AppEmptyState(
                          title: state.categories.isEmpty
                              ? 'Belum ada kategori'
                              : 'Kategori tidak ditemukan',
                          message: state.categories.isEmpty
                              ? 'Tambahkan kategori pertama untuk merapikan katalog POS.'
                              : 'Coba kata kunci atau status yang berbeda.',
                          icon: state.categories.isEmpty
                              ? Icons.category_outlined
                              : Icons.search_off_rounded,
                          onAction: state.categories.isEmpty
                              ? () => _openCategoryForm()
                              : _clearFilters,
                          actionLabel: state.categories.isEmpty
                              ? 'Tambah kategori'
                              : 'Hapus filter',
                        )
                      : RefreshIndicator(
                          onRefresh: () => ref
                              .read(productManagementProvider.notifier)
                              .refresh(),
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              final productCount = state.products
                                  .where(
                                    (product) =>
                                        product.categoryId == category.id,
                                  )
                                  .length;
                              final childCount = state.categories
                                  .where(
                                    (child) => child.parentId == category.id,
                                  )
                                  .length;
                              return _CategoryRow(
                                category: category,
                                parentName: byId[category.parentId]?.name,
                                depth: _categoryDepth(category, byId),
                                productCount: productCount,
                                childCount: childCount,
                                onEdit: () => _openCategoryForm(category),
                                onToggle: () => _toggleCategory(category),
                                onDelete: () => _confirmDelete(category),
                                enabled: !_isMutating,
                              );
                            },
                          ),
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

  Future<void> _openCategoryForm([CategoryModel? category]) async {
    final state = ref.read(productManagementProvider).value;
    if (state == null) return;
    final draft = await AppBottomSheet.show<CategoryDraft>(
      context,
      title: category == null ? 'Kategori baru' : 'Edit kategori',
      subtitle: 'Atur pengelompokan dan urutan menu di POS',
      child: _CategoryForm(category: category, categories: state.categories),
    );
    if (draft == null || !mounted) return;

    setState(() => _isMutating = true);
    final notifier = ref.read(productManagementProvider.notifier);
    final result = category == null
        ? await notifier.createCategory(draft)
        : await notifier.updateCategory(category, draft);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _toggleCategory(CategoryModel category) async {
    setState(() => _isMutating = true);
    final draft = CategoryDraft.fromCategory(
      category,
    ).copyWith(isActive: !category.isActive);
    final result = await ref
        .read(productManagementProvider.notifier)
        .updateCategory(category, draft);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _confirmDelete(CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus kategori?'),
        content: Text(
          '${category.name} akan dihapus. Kategori yang masih memiliki subkategori atau digunakan produk tidak dapat dihapus.',
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
    final result = await ref
        .read(productManagementProvider.notifier)
        .deleteCategory(category);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  void _showResult(ProductMutationResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
  }
}

class _CategoryOfflineNotice extends StatelessWidget {
  const _CategoryOfflineNotice({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Menampilkan cache lokal. Hubungkan ke server sebelum mengubah kategori.',
            ),
          ),
          IconButton(
            tooltip: 'Coba hubungkan kembali',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.parentName,
    required this.depth,
    required this.productCount,
    required this.childCount,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.enabled,
  });

  final CategoryModel category;
  final String? parentName;
  final int depth;
  final int productCount;
  final int childCount;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: (depth.clamp(0, 2) * 14).toDouble()),
      child: AppCard(
        onTap: enabled ? onEdit : null,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                parentName == null
                    ? Icons.category_outlined
                    : Icons.subdirectory_arrow_right_rounded,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    parentName == null
                        ? 'Kategori utama - urutan ${category.sortOrder}'
                        : 'Di dalam $parentName - urutan ${category.sortOrder}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      AppBadge(
                        text: category.isActive ? 'Aktif' : 'Nonaktif',
                        icon: category.isActive
                            ? Icons.check_circle_outline_rounded
                            : Icons.pause_circle_outline_rounded,
                        color: category.isActive
                            ? AppColors.successSoft
                            : AppColors.surfaceMuted,
                        textColor: category.isActive
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      AppBadge(text: '$productCount produk'),
                      if (childCount > 0)
                        AppBadge(text: '$childCount subkategori'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'Aksi kategori',
              enabled: enabled,
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'toggle') onToggle();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      category.isActive
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    title: Text(category.isActive ? 'Nonaktifkan' : 'Aktifkan'),
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
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({required this.category, required this.categories});

  final CategoryModel? category;
  final List<CategoryModel> categories;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sortOrder;
  String? _parentId;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _name = TextEditingController(text: category?.name);
    _sortOrder = TextEditingController(
      text: (category?.sortOrder ?? 0).toString(),
    );
    _parentId = category?.parentId;
    _isActive = category?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blockedIds =
        widget.category == null
              ? <String>{}
              : _descendantIds(widget.categories, widget.category!.id)
          ..add(widget.category!.id);
    final parentOptions =
        widget.categories
            .where((category) => !blockedIds.contains(category.id))
            .toList()
          ..sort((left, right) => left.name.compareTo(right.name));
    if (_parentId != null &&
        !parentOptions.any((category) => category.id == _parentId)) {
      _parentId = null;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nama kategori',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Nama minimal 2 karakter'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _parentId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kategori induk',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tanpa induk'),
                ),
                ...parentOptions.map(
                  (category) => DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _parentId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sortOrder,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Urutan tampil',
                prefixIcon: Icon(Icons.format_list_numbered_rounded),
              ),
              validator: (value) => int.tryParse(value ?? '') == null
                  ? 'Masukkan urutan yang valid'
                  : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kategori aktif'),
              subtitle: const Text('Kategori aktif tersedia di katalog POS'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            const SizedBox(height: 16),
            AppButton(
              text: widget.category == null
                  ? 'Tambah kategori'
                  : 'Simpan perubahan',
              icon: Icons.check_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      CategoryDraft(
        name: _name.text,
        parentId: _parentId,
        sortOrder: int.parse(_sortOrder.text),
        isActive: _isActive,
      ),
    );
  }
}

List<CategoryModel> _orderedCategories(List<CategoryModel> categories) {
  final byParent = <String?, List<CategoryModel>>{};
  final ids = categories.map((category) => category.id).toSet();
  for (final category in categories) {
    final parentId = ids.contains(category.parentId) ? category.parentId : null;
    byParent.putIfAbsent(parentId, () => []).add(category);
  }
  for (final children in byParent.values) {
    children.sort((left, right) {
      final byOrder = left.sortOrder.compareTo(right.sortOrder);
      return byOrder != 0 ? byOrder : left.name.compareTo(right.name);
    });
  }

  final ordered = <CategoryModel>[];
  final visited = <String>{};
  void appendChildren(String? parentId) {
    for (final category in byParent[parentId] ?? const <CategoryModel>[]) {
      if (!visited.add(category.id)) continue;
      ordered.add(category);
      appendChildren(category.id);
    }
  }

  appendChildren(null);
  for (final category in categories) {
    if (visited.add(category.id)) ordered.add(category);
  }
  return ordered;
}

int _categoryDepth(CategoryModel category, Map<String, CategoryModel> byId) {
  var depth = 0;
  var parentId = category.parentId;
  final visited = <String>{category.id};
  while (parentId != null && visited.add(parentId)) {
    final parent = byId[parentId];
    if (parent == null) break;
    depth++;
    parentId = parent.parentId;
  }
  return depth;
}

Set<String> _descendantIds(List<CategoryModel> categories, String categoryId) {
  final result = <String>{};
  final queue = <String>[categoryId];
  while (queue.isNotEmpty) {
    final parentId = queue.removeLast();
    for (final category in categories) {
      if (category.parentId == parentId && result.add(category.id)) {
        queue.add(category.id);
      }
    }
  }
  return result;
}
