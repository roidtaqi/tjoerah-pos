class InventoryItemModel {
  final int id;
  final String name;
  final String sku;
  final String itemType;
  final String unit;
  final double weightedAverageCost;
  final double minimumStock;
  final double currentStock;

  InventoryItemModel({
    required this.id,
    required this.name,
    required this.sku,
    required this.itemType,
    required this.unit,
    required this.weightedAverageCost,
    required this.minimumStock,
    required this.currentStock,
  });

  bool get isLowStock => currentStock < minimumStock;

  factory InventoryItemModel.fromJson(Map<String, dynamic> json) {
    return InventoryItemModel(
      id: json['id'] as int,
      name: json['name'] as String,
      sku: json['sku'] as String? ?? '',
      itemType: json['item_type'] as String? ?? 'raw_material',
      unit: json['unit'] as String? ?? 'pcs',
      weightedAverageCost: double.parse(
        (json['weighted_average_cost'] ?? 0).toString(),
      ),
      minimumStock: double.parse((json['minimum_stock'] ?? 0).toString()),
      currentStock: double.parse((json['current_stock'] ?? 0).toString()),
    );
  }
}

class StockMovementModel {
  final int id;
  final int itemId;
  final String itemName;
  final String type;
  final double quantity;
  final double beforeQty;
  final double afterQty;
  final String date;
  final String? reason;

  StockMovementModel({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.type,
    required this.quantity,
    required this.beforeQty,
    required this.afterQty,
    required this.date,
    this.reason,
  });

  factory StockMovementModel.fromJson(Map<String, dynamic> json) {
    final item = json['inventory_item'] as Map<String, dynamic>?;
    return StockMovementModel(
      id: json['id'] as int,
      itemId: json['inventory_item_id'] as int,
      itemName: item != null ? item['name'] as String : 'Unknown Item',
      type: json['movement_type'] as String,
      quantity: double.parse(json['quantity'].toString()),
      beforeQty: double.parse((json['before_quantity'] ?? 0).toString()),
      afterQty: double.parse((json['after_quantity'] ?? 0).toString()),
      date: json['created_at'] as String,
      reason: json['reason'] as String?,
    );
  }
}
