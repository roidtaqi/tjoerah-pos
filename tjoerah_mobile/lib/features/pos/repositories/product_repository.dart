import '../../../core/database/database_helper.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';

class ProductRepository {
  Future<List<ProductModel>> getProducts({
    String? categoryId,
    bool includeInactive = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final filters = <String>[];
    final arguments = <Object?>[];
    if (categoryId != null) {
      filters.add('category_id = ?');
      arguments.add(categoryId);
    }
    if (!includeInactive) filters.add('is_active = 1');

    final rows = await db.query(
      'products',
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: filters.isEmpty ? null : arguments,
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map((row) => ProductModel.fromSqlite(row)).toList();
  }

  Future<List<CategoryModel>> getCategories() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('categories', orderBy: 'sort_order ASC');

    return rows.map((row) => CategoryModel.fromJson(row)).toList();
  }
}
