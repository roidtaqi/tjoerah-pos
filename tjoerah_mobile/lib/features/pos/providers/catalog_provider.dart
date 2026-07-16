import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/sync_service.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

class CatalogState {
  const CatalogState({
    this.products = const [],
    this.categories = const [],
    this.selectedCategoryId,
    this.searchQuery = '',
  });

  final List<ProductModel> products;
  final List<CategoryModel> categories;
  final String? selectedCategoryId;
  final String searchQuery;

  CatalogState copyWith({
    List<ProductModel>? products,
    List<CategoryModel>? categories,
    String? selectedCategoryId,
    bool clearCategory = false,
    String? searchQuery,
  }) {
    return CatalogState(
      products: products ?? this.products,
      categories: categories ?? this.categories,
      selectedCategoryId: clearCategory
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<ProductModel> get filteredProducts {
    final query = searchQuery.trim().toLowerCase();
    return products.where((product) {
      final inCategory =
          selectedCategoryId == null ||
          product.categoryId == selectedCategoryId;
      final matchesQuery =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          (product.sku?.toLowerCase().contains(query) ?? false);
      return inCategory && matchesQuery;
    }).toList();
  }
}

class CatalogNotifier extends AsyncNotifier<CatalogState> {
  final ProductRepository _repository = ProductRepository();

  @override
  Future<CatalogState> build() => _loadFromLocal();

  Future<CatalogState> _loadFromLocal() async {
    final products = await _repository.getProducts();
    final categories = await _repository.getCategories();
    final current = state.value;
    return CatalogState(
      products: products,
      categories: categories,
      selectedCategoryId: current?.selectedCategoryId,
      searchQuery: current?.searchQuery ?? '',
    );
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadFromLocal);
  }

  Future<void> syncFromServer() async {
    final previous = state.value;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final success = await SyncService.syncCatalog();
      if (!success) throw Exception('Sinkronisasi katalog gagal.');
      final result = await _loadFromLocal();
      return result.copyWith(
        selectedCategoryId: previous?.selectedCategoryId,
        clearCategory: previous?.selectedCategoryId == null,
        searchQuery: previous?.searchQuery,
      );
    });
  }

  void selectCategory(String? categoryId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        selectedCategoryId: categoryId,
        clearCategory: categoryId == null,
      ),
    );
  }

  void search(String query) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(searchQuery: query));
  }
}

final catalogProvider = AsyncNotifierProvider<CatalogNotifier, CatalogState>(
  CatalogNotifier.new,
);
