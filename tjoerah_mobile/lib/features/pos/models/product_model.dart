class ProductModel {
  const ProductModel({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.categoryId,
    this.sku,
    this.barcode,
    this.imageUrl,
    this.productType = 'simple',
    this.station,
    this.slaMinutes,
    this.trackInventory = true,
    this.isActive = true,
  });

  final String id;
  final String name;
  final double price;
  final String? description;
  final String? categoryId;
  final String? sku;
  final String? barcode;
  final String? imageUrl;
  final String productType;
  final String? station;
  final int? slaMinutes;
  final bool trackInventory;
  final bool isActive;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      price: _asDouble(json['base_price'] ?? json['price']),
      description: _asNullableString(json['description']),
      categoryId: _asNullableString(json['category_id']),
      sku: _asNullableString(json['sku']),
      barcode: _asNullableString(json['barcode']),
      imageUrl: _asNullableString(json['image_url']),
      productType: _asNullableString(json['product_type']) ?? 'simple',
      station: _asNullableString(json['station']),
      slaMinutes: _asNullableInt(json['sla_minutes']),
      trackInventory: _asBool(json['track_inventory'], fallback: true),
      isActive: _asBool(json['is_active'], fallback: true),
    );
  }

  factory ProductModel.fromSqlite(Map<String, dynamic> row) {
    return ProductModel(
      id: row['id'].toString(),
      name: row['name']?.toString() ?? '',
      price: _asDouble(row['price']),
      description: _asNullableString(row['description']),
      categoryId: _asNullableString(row['category_id']),
      sku: _asNullableString(row['sku']),
      barcode: _asNullableString(row['barcode']),
      imageUrl: _asNullableString(row['image_url']),
      productType: _asNullableString(row['product_type']) ?? 'simple',
      station: _asNullableString(row['station']),
      slaMinutes: _asNullableInt(row['sla_minutes']),
      trackInventory: _asBool(row['track_inventory'], fallback: true),
      isActive: _asBool(row['is_active'], fallback: true),
    );
  }

  Map<String, dynamic> toSqlite() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'description': description,
      'category_id': categoryId,
      'sku': sku,
      'barcode': barcode,
      'image_url': imageUrl,
      'product_type': productType,
      'station': station,
      'sla_minutes': slaMinutes,
      'track_inventory': trackInventory ? 1 : 0,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.price,
    this.description,
    this.categoryId,
    this.sku,
    this.barcode,
    this.imageUrl,
    this.productType = 'simple',
    this.station,
    this.slaMinutes,
    this.trackInventory = true,
    this.isActive = true,
  });

  factory ProductDraft.fromProduct(ProductModel product) {
    return ProductDraft(
      name: product.name,
      price: product.price,
      description: product.description,
      categoryId: product.categoryId,
      sku: product.sku,
      barcode: product.barcode,
      imageUrl: product.imageUrl,
      productType: product.productType,
      station: product.station,
      slaMinutes: product.slaMinutes,
      trackInventory: product.trackInventory,
      isActive: product.isActive,
    );
  }

  final String name;
  final double price;
  final String? description;
  final String? categoryId;
  final String? sku;
  final String? barcode;
  final String? imageUrl;
  final String productType;
  final String? station;
  final int? slaMinutes;
  final bool trackInventory;
  final bool isActive;

  ProductDraft copyWith({bool? isActive}) {
    return ProductDraft(
      name: name,
      price: price,
      description: description,
      categoryId: categoryId,
      sku: sku,
      barcode: barcode,
      imageUrl: imageUrl,
      productType: productType,
      station: station,
      slaMinutes: slaMinutes,
      trackInventory: trackInventory,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'description': _trimmedOrNull(description),
      'category_id': categoryId,
      'base_price': price,
      'sku': _trimmedOrNull(sku),
      'barcode': _trimmedOrNull(barcode),
      'image_url': _trimmedOrNull(imageUrl),
      'product_type': productType,
      'station': station,
      'sla_minutes': slaMinutes,
      'track_inventory': trackInventory,
      'is_active': isActive,
    };
  }
}

double _asDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int? _asNullableInt(dynamic value) {
  if (value == null || '$value'.trim().isEmpty) return null;
  return value is int ? value : int.tryParse('$value');
}

bool _asBool(dynamic value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains(value.toString().toLowerCase());
}

String? _asNullableString(dynamic value) => _trimmedOrNull(value?.toString());

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
