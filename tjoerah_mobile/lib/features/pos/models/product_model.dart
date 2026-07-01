class ProductModel {
  final String id;
  final String name;
  final double price;
  final String? categoryId;
  final String? sku;
  final String? station;

  ProductModel({
    required this.id,
    required this.name,
    required this.price,
    this.categoryId,
    this.sku,
    this.station,
  });

  /// Maps from API JSON (snake_case keys: base_price, category_id).
  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      name: json['name'] as String,
      price: (json['base_price'] as num).toDouble(),
      categoryId: json['category_id'] as String?,
      sku: json['sku'] as String?,
      station: json['station'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'base_price': price,
      'category_id': categoryId,
      'sku': sku,
      'station': station,
    };
  }

  /// Maps from a SQLite row (column names match the `products` table).
  factory ProductModel.fromSqlite(Map<String, dynamic> row) {
    return ProductModel(
      id: row['id'] as String,
      name: row['name'] as String,
      price: (row['price'] as num).toDouble(),
      categoryId: row['category_id'] as String?,
      sku: row['sku'] as String?,
      station: row['station'] as String?,
    );
  }

  /// Maps for SQLite insert into the `products` table.
  Map<String, dynamic> toSqlite() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'category_id': categoryId,
      'sku': sku,
      'station': station,
    };
  }
}
