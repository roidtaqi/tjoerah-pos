import 'package:flutter/material.dart';

import '../models/product_model.dart';
import '../models/category_model.dart';
import '../repositories/product_repository.dart';

class CatalogProvider with ChangeNotifier {
  final ProductRepository _repo = ProductRepository();

  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  String? _selectedCategoryId;
  bool _isLoading = false;
  String? _error;

  CatalogProvider() {
    loadFromLocal();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  List<ProductModel> get products => _products;
  List<CategoryModel> get categories => _categories;
  String? get selectedCategoryId => _selectedCategoryId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Returns products filtered by the currently selected category.
  /// If no category is selected, returns all products.
  List<ProductModel> get filteredProducts {
    if (_selectedCategoryId == null) {
      return _products;
    }
    return _products
        .where((p) => p.categoryId == _selectedCategoryId)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Loads products and categories from the local SQLite database.
  Future<void> loadFromLocal() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _products = await _repo.getProducts();
      _categories = await _repo.getCategories();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Syncs the catalog from the remote server, then reloads from local.
  Future<void> syncFromServer() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _repo.syncFromServer();
      await loadFromLocal();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the active category filter and notifies listeners.
  void selectCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }
}
