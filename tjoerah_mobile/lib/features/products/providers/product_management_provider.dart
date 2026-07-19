import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/sync_service.dart';
import '../../pos/models/category_model.dart';
import '../../pos/models/product_model.dart';
import '../../pos/providers/catalog_provider.dart';
import '../../pos/repositories/product_repository.dart';

class ProductManagementState {
  const ProductManagementState({
    this.products = const [],
    this.categories = const [],
    this.isFromCache = false,
  });

  final List<ProductModel> products;
  final List<CategoryModel> categories;
  final bool isFromCache;
}

class ProductMutationResult {
  const ProductMutationResult._(this.isSuccess, this.message);

  const ProductMutationResult.success(String message) : this._(true, message);

  const ProductMutationResult.failure(String message) : this._(false, message);

  final bool isSuccess;
  final String message;
}

class ProductManagementNotifier extends AsyncNotifier<ProductManagementState> {
  final ProductRepository _localRepository = ProductRepository();

  @override
  Future<ProductManagementState> build() async {
    try {
      return await _loadRemote();
    } catch (_) {
      return _loadLocal();
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _loadRemote());
    } catch (_) {
      state = AsyncValue.data(await _loadLocal());
    }
  }

  Future<ProductMutationResult> createProduct(ProductDraft draft) async {
    try {
      final response = await ApiClient.post('/products', draft.toJson());
      if (response.statusCode != 201) {
        return ProductMutationResult.failure(_responseMessage(response.body));
      }

      final catalogSynced = await _syncAfterMutation();
      return ProductMutationResult.success(
        catalogSynced
            ? '${draft.name} berhasil ditambahkan.'
            : '${draft.name} tersimpan. Sinkronkan katalog POS saat koneksi stabil.',
      );
    } catch (_) {
      return const ProductMutationResult.failure(
        'Produk belum dapat ditambahkan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<ProductMutationResult> updateProduct(
    ProductModel product,
    ProductDraft draft,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/products/${product.id}',
        draft.toJson(),
      );
      if (response.statusCode != 200) {
        return ProductMutationResult.failure(_responseMessage(response.body));
      }

      final catalogSynced = await _syncAfterMutation();
      return ProductMutationResult.success(
        catalogSynced
            ? '${draft.name} berhasil diperbarui.'
            : '${draft.name} diperbarui. Sinkronkan katalog POS saat koneksi stabil.',
      );
    } catch (_) {
      return const ProductMutationResult.failure(
        'Perubahan belum dapat disimpan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<ProductMutationResult> deleteProduct(ProductModel product) async {
    try {
      final response = await ApiClient.delete('/products/${product.id}');
      if (response.statusCode != 204) {
        return ProductMutationResult.failure(_responseMessage(response.body));
      }

      final catalogSynced = await _syncAfterMutation();
      return ProductMutationResult.success(
        catalogSynced
            ? '${product.name} berhasil dihapus.'
            : '${product.name} dihapus. Sinkronkan katalog POS saat koneksi stabil.',
      );
    } catch (_) {
      return const ProductMutationResult.failure(
        'Produk belum dapat dihapus. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<ProductMutationResult> createCategory(CategoryDraft draft) async {
    try {
      final response = await ApiClient.post('/categories', draft.toJson());
      if (response.statusCode != 201) {
        return ProductMutationResult.failure(_responseMessage(response.body));
      }

      final catalogSynced = await _syncAfterMutation();
      return ProductMutationResult.success(
        catalogSynced
            ? '${draft.name} berhasil ditambahkan.'
            : '${draft.name} tersimpan. Sinkronkan katalog POS saat koneksi stabil.',
      );
    } catch (_) {
      return const ProductMutationResult.failure(
        'Kategori belum dapat ditambahkan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<ProductMutationResult> updateCategory(
    CategoryModel category,
    CategoryDraft draft,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/categories/${category.id}',
        draft.toJson(),
      );
      if (response.statusCode != 200) {
        return ProductMutationResult.failure(_responseMessage(response.body));
      }

      final catalogSynced = await _syncAfterMutation();
      return ProductMutationResult.success(
        catalogSynced
            ? '${draft.name} berhasil diperbarui.'
            : '${draft.name} diperbarui. Sinkronkan katalog POS saat koneksi stabil.',
      );
    } catch (_) {
      return const ProductMutationResult.failure(
        'Perubahan kategori belum dapat disimpan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<ProductMutationResult> deleteCategory(CategoryModel category) async {
    try {
      final response = await ApiClient.delete('/categories/${category.id}');
      if (response.statusCode != 204) {
        return ProductMutationResult.failure(_responseMessage(response.body));
      }

      final catalogSynced = await _syncAfterMutation();
      return ProductMutationResult.success(
        catalogSynced
            ? '${category.name} berhasil dihapus.'
            : '${category.name} dihapus. Sinkronkan katalog POS saat koneksi stabil.',
      );
    } catch (_) {
      return const ProductMutationResult.failure(
        'Kategori belum dapat dihapus. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<ProductManagementState> _loadRemote() async {
    final results = await Future.wait([_fetchProducts(), _fetchCategories()]);
    return ProductManagementState(
      products: results[0] as List<ProductModel>,
      categories: results[1] as List<CategoryModel>,
    );
  }

  Future<ProductManagementState> _loadLocal() async {
    return ProductManagementState(
      products: await _localRepository.getProducts(includeInactive: true),
      categories: await _localRepository.getCategories(),
      isFromCache: true,
    );
  }

  Future<List<ProductModel>> _fetchProducts() async {
    final products = <ProductModel>[];
    var page = 1;
    var lastPage = 1;

    do {
      final response = await ApiClient.get(
        '/products?status=all&per_page=100&page=$page',
      );
      if (response.statusCode != 200) throw Exception(response.body);
      final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      final rows = body['data'] as List? ?? const [];
      products.addAll(
        rows.whereType<Map>().map(
          (row) => ProductModel.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
      lastPage = _asInt(body['last_page'], fallback: page);
      page++;
    } while (page <= lastPage);

    return products;
  }

  Future<List<CategoryModel>> _fetchCategories() async {
    final categories = <CategoryModel>[];
    var page = 1;
    var lastPage = 1;

    do {
      final response = await ApiClient.get(
        '/categories?per_page=100&page=$page',
      );
      if (response.statusCode != 200) throw Exception(response.body);
      final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      final rows = body['data'] as List? ?? const [];
      for (final row in rows.whereType<Map>()) {
        _appendCategoryTree(categories, Map<String, dynamic>.from(row));
      }
      lastPage = _asInt(body['last_page'], fallback: page);
      page++;
    } while (page <= lastPage);

    final unique = <String, CategoryModel>{
      for (final category in categories) category.id: category,
    };
    final result = unique.values.toList();
    result.sort((left, right) {
      final byOrder = left.sortOrder.compareTo(right.sortOrder);
      return byOrder != 0 ? byOrder : left.name.compareTo(right.name);
    });
    return result;
  }

  Future<bool> _syncAfterMutation() async {
    final catalogSynced = await SyncService.syncCatalog();
    ref.invalidate(catalogProvider);
    try {
      state = AsyncValue.data(await _loadRemote());
    } catch (_) {
      state = AsyncValue.data(await _loadLocal());
    }
    return catalogSynced;
  }

  void _appendCategoryTree(
    List<CategoryModel> target,
    Map<String, dynamic> row,
  ) {
    target.add(CategoryModel.fromJson(row));
    final children = row['children'] as List? ?? const [];
    for (final child in children.whereType<Map>()) {
      _appendCategoryTree(target, Map<String, dynamic>.from(child));
    }
  }

  int _asInt(dynamic value, {required int fallback}) {
    return value is int ? value : int.tryParse('$value') ?? fallback;
  }

  String _responseMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final messages in errors.values) {
            if (messages is List && messages.isNotEmpty) {
              return messages.first.toString();
            }
          }
        }
        final message = decoded['message'];
        if (message != null) return message.toString();
      }
    } catch (_) {
      // The fallback below is clearer than a non-JSON server response.
    }
    return 'Permintaan belum dapat diproses. Coba lagi.';
  }
}

final productManagementProvider =
    AsyncNotifierProvider<ProductManagementNotifier, ProductManagementState>(
      ProductManagementNotifier.new,
    );
