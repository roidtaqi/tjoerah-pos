import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/local_db.dart';
import '../../../core/network/api_client.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';

class ProductRepository {
  /// Returns products from local SQLite, optionally filtered by [categoryId].
  Future<List<ProductModel>> getProducts({String? categoryId}) async {
    final db = await LocalDatabase.instance.database;

    List<Map<String, dynamic>> rows;

    if (categoryId != null) {
      rows = await db.query(
        'products',
        where: 'category_id = ?',
        whereArgs: [categoryId],
      );
    } else {
      rows = await db.query('products');
    }

    return rows.map((row) => ProductModel.fromSqlite(row)).toList();
  }

  /// Returns categories from local SQLite.
  Future<List<CategoryModel>> getCategories() async {
    final db = await LocalDatabase.instance.database;
    await _ensureCategoriesTable(db);

    final rows = await db.query('categories');
    return rows.map((row) => CategoryModel.fromJson(row)).toList();
  }

  /// Calls the server sync endpoint and upserts products & categories locally.
  Future<void> syncFromServer() async {
    final response = await ApiClient.get('/catalog/sync');

    if (response.statusCode != 200) {
      throw Exception('Catalog sync failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final db = await LocalDatabase.instance.database;

    // --- Upsert categories ---
    await _ensureCategoriesTable(db);

    final categoriesJson = data['categories'] as List<dynamic>? ?? [];
    for (final catJson in categoriesJson) {
      final category = CategoryModel.fromJson(catJson as Map<String, dynamic>);
      await db.insert(
        'categories',
        category.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // --- Upsert products ---
    final productsJson = data['products'] as List<dynamic>? ?? [];
    for (final prodJson in productsJson) {
      final product = ProductModel.fromJson(prodJson as Map<String, dynamic>);
      await db.insert(
        'products',
        product.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Creates the categories table if it doesn't exist yet.
  Future<void> _ensureCategoriesTable(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
  }
}
