import '../../../core/database/database_helper.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';

class ProductRepository {
  Future<List<ProductModel>> getProducts({String? categoryId}) async {
    final db = await DatabaseHelper.instance.database;
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

  Future<List<CategoryModel>> getCategories() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('categories', orderBy: 'sort_order ASC');

    return rows.map((row) => CategoryModel.fromJson(row)).toList();
  }
}
