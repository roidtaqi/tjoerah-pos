import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
import '../../pos/models/product_model.dart';
import '../providers/product_management_provider.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
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
    if (!canManageProductsForUser(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kelola produk')),
        body: const AppErrorState(
          title: 'Akses dibatasi',
          message: 'Hanya owner atau admin yang dapat mengelola produk.',
        ),
      );
    }

    final catalog = ref.watch(productManagementProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola produk'),
        actions: [
          IconButton(
            tooltip: 'Kelola kategori',
            onPressed: _isMutating
                ? null
                : () => context.push('/categories/manage'),
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            tooltip: 'Muat ulang produk',
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
        onPressed: _isMutating ? null : () => _openProductForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah produk'),
      ),
      body: catalog.when(
        loading: () => const AppLoadingState(message: 'Memuat produk...'),
        error: (_, _) => AppErrorState(
          message: 'Produk belum dapat dimuat dari server.',
          onRetry: () => ref.read(productManagementProvider.notifier).refresh(),
        ),
        data: _buildCatalog,
      ),
    );
  }

  Widget _buildCatalog(ProductManagementState state) {
    final query = _query.trim().toLowerCase();
    final products = state.products.where((product) {
      final matchesStatus =
          _status == 'all' ||
          (_status == 'active' && product.isActive) ||
          (_status == 'inactive' && !product.isActive);
      final matchesQuery =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.toLowerCase().contains(query) ?? false);
      return matchesStatus && matchesQuery;
    }).toList();
    final categories = {
      for (final category in state.categories) category.id: category.name,
    };
    final activeCount = state.products
        .where((product) => product.isActive)
        .length;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: AppSpacing.page(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.isFromCache) ...[
                  _OfflineNotice(
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
                        hintText: 'Cari nama, SKU, atau barcode',
                        onChanged: (value) => setState(() => _query = value),
                        onClear: () => setState(() => _query = ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${products.length} produk',
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
                        label: Text('Semua ${state.products.length}'),
                      ),
                      ButtonSegment(
                        value: 'active',
                        label: Text('Aktif $activeCount'),
                      ),
                      ButtonSegment(
                        value: 'inactive',
                        label: Text(
                          'Nonaktif ${state.products.length - activeCount}',
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
                  child: products.isEmpty
                      ? AppEmptyState(
                          title: state.products.isEmpty
                              ? 'Belum ada produk'
                              : 'Produk tidak ditemukan',
                          message: state.products.isEmpty
                              ? 'Tambahkan produk pertama untuk mengisi katalog POS.'
                              : 'Coba kata kunci atau status yang berbeda.',
                          icon: state.products.isEmpty
                              ? Icons.restaurant_menu_rounded
                              : Icons.search_off_rounded,
                          onAction: state.products.isEmpty
                              ? () => _openProductForm()
                              : _clearFilters,
                          actionLabel: state.products.isEmpty
                              ? 'Tambah produk'
                              : 'Hapus filter',
                        )
                      : RefreshIndicator(
                          onRefresh: () => ref
                              .read(productManagementProvider.notifier)
                              .refresh(),
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: products.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return _ProductRow(
                                product: product,
                                categoryName:
                                    categories[product.categoryId] ??
                                    'Tanpa kategori',
                                onEdit: () => _openProductForm(product),
                                onToggle: () => _toggleProduct(product),
                                onDelete: () => _confirmDelete(product),
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

  Future<void> _openProductForm([ProductModel? product]) async {
    final state = ref.read(productManagementProvider).value;
    if (state == null) return;
    final draft = await AppBottomSheet.show<ProductDraft>(
      context,
      title: product == null ? 'Produk baru' : 'Edit produk',
      subtitle: 'Lengkapi informasi yang digunakan di POS dan produksi',
      child: _ProductForm(product: product, categories: state.categories),
    );
    if (draft == null || !mounted) return;

    setState(() => _isMutating = true);
    final notifier = ref.read(productManagementProvider.notifier);
    final result = product == null
        ? await notifier.createProduct(draft)
        : await notifier.updateProduct(product, draft);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _toggleProduct(ProductModel product) async {
    setState(() => _isMutating = true);
    final result = await ref
        .read(productManagementProvider.notifier)
        .updateProduct(
          product,
          ProductDraft.fromProduct(
            product,
          ).copyWith(isActive: !product.isActive),
        );
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _confirmDelete(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus produk?'),
        content: Text(
          '${product.name} akan dihapus dari katalog. Riwayat transaksi lama tetap tersimpan.',
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
        .deleteProduct(product);
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

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.onRefresh});

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
              'Menampilkan cache lokal. Hubungkan ke server sebelum mengubah produk.',
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

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.categoryName,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.enabled,
  });

  final ProductModel product;
  final String categoryName;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return AppCard(
      onTap: enabled ? onEdit : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _stationIcon(product.station),
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '$categoryName - ${currency.format(product.price)}',
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
                      text: product.isActive ? 'Aktif' : 'Nonaktif',
                      icon: product.isActive
                          ? Icons.check_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      color: product.isActive
                          ? AppColors.successSoft
                          : AppColors.surfaceMuted,
                      textColor: product.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    if (product.sku != null) AppBadge(text: product.sku!),
                    AppBadge(text: _stationLabel(product.station)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Aksi produk',
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
                    product.isActive
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                  ),
                  title: Text(product.isActive ? 'Nonaktifkan' : 'Aktifkan'),
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
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({required this.product, required this.categories});

  final ProductModel? product;
  final List<CategoryModel> categories;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _imageUrl;
  late final TextEditingController _sla;
  String? _categoryId;
  String _productType = 'simple';
  String? _station;
  bool _trackInventory = true;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name);
    _description = TextEditingController(text: product?.description);
    _price = TextEditingController(
      text: product == null
          ? ''
          : product.price.toStringAsFixed(product.price % 1 == 0 ? 0 : 2),
    );
    _sku = TextEditingController(text: product?.sku);
    _barcode = TextEditingController(text: product?.barcode);
    _imageUrl = TextEditingController(text: product?.imageUrl);
    _sla = TextEditingController(text: product?.slaMinutes?.toString());
    _categoryId =
        widget.categories.any((category) => category.id == product?.categoryId)
        ? product?.categoryId
        : null;
    _productType =
        const {
          'simple',
          'variant',
          'combo',
          'bundle',
        }.contains(product?.productType)
        ? product!.productType
        : 'simple';
    _station = const {'bar', 'kitchen'}.contains(product?.station)
        ? product?.station
        : null;
    _trackInventory = product?.trackInventory ?? true;
    _isActive = product?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _sku.dispose();
    _barcode.dispose();
    _imageUrl.dispose();
    _sla.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Informasi utama',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nama produk',
                prefixIcon: Icon(Icons.restaurant_menu_rounded),
              ),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Nama minimal 2 karakter'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Deskripsi',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tanpa kategori'),
                ),
                ...widget.categories.map(
                  (category) => DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Harga jual',
                prefixText: 'Rp ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final price = double.tryParse(value ?? '');
                return price == null || price < 0
                    ? 'Masukkan harga yang valid'
                    : null;
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Identitas & produksi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sku,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'SKU',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Barcode',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _productType,
              decoration: const InputDecoration(
                labelText: 'Tipe produk',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'simple', child: Text('Sederhana')),
                DropdownMenuItem(value: 'variant', child: Text('Varian')),
                DropdownMenuItem(value: 'combo', child: Text('Kombo')),
                DropdownMenuItem(value: 'bundle', child: Text('Bundel')),
              ],
              onChanged: (value) =>
                  setState(() => _productType = value ?? 'simple'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _station,
              decoration: const InputDecoration(
                labelText: 'Stasiun produksi',
                prefixIcon: Icon(Icons.soup_kitchen_outlined),
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tanpa stasiun'),
                ),
                DropdownMenuItem(value: 'bar', child: Text('Bar')),
                DropdownMenuItem(value: 'kitchen', child: Text('Dapur')),
              ],
              onChanged: (value) => setState(() => _station = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sla,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Target waktu produksi',
                suffixText: 'menit',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) return null;
                final minutes = int.tryParse(value!);
                return minutes == null || minutes < 1 || minutes > 1440
                    ? 'Gunakan nilai 1 sampai 1440 menit'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imageUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL gambar',
                prefixIcon: Icon(Icons.image_outlined),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                final uri = Uri.tryParse(text);
                return uri == null ||
                        !const {'http', 'https'}.contains(uri.scheme) ||
                        uri.host.isEmpty
                    ? 'Masukkan URL http atau https yang valid'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lacak persediaan'),
              subtitle: const Text(
                'Kurangi stok berdasarkan resep saat terjual',
              ),
              value: _trackInventory,
              onChanged: (value) => setState(() => _trackInventory = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Produk aktif'),
              subtitle: const Text('Produk aktif tersedia di katalog POS'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            const SizedBox(height: 16),
            AppButton(
              text: widget.product == null
                  ? 'Tambah produk'
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
      ProductDraft(
        name: _name.text,
        description: _description.text,
        categoryId: _categoryId,
        price: double.parse(_price.text),
        sku: _sku.text,
        barcode: _barcode.text,
        imageUrl: _imageUrl.text,
        productType: _productType,
        station: _station,
        slaMinutes: int.tryParse(_sla.text),
        trackInventory: _trackInventory,
        isActive: _isActive,
      ),
    );
  }
}

IconData _stationIcon(String? station) => switch (station) {
  'bar' => Icons.local_cafe_outlined,
  'kitchen' => Icons.restaurant_outlined,
  _ => Icons.fastfood_outlined,
};

String _stationLabel(String? station) => switch (station) {
  'bar' => 'Bar',
  'kitchen' => 'Dapur',
  _ => 'Tanpa stasiun',
};
