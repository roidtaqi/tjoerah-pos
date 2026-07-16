class RecipeModel {
  final String id;
  final String? productId;
  final String name;
  final double currentCost;
  final double yieldQuantity;
  final String? yieldUnit;
  final List<RecipeItemModel> items;

  RecipeModel({
    required this.id,
    this.productId,
    required this.name,
    required this.currentCost,
    required this.yieldQuantity,
    this.yieldUnit,
    this.items = const [],
  });
}

class RecipeItemModel {
  final String id;
  final String recipeId;
  final String? inventoryItemId;
  final String? inventoryItemName;
  final double quantity;
  final String? unit;
  final double wastePercent;
  final double unitCost;
  final double totalCost;

  RecipeItemModel({
    required this.id,
    required this.recipeId,
    this.inventoryItemId,
    this.inventoryItemName,
    required this.quantity,
    this.unit,
    required this.wastePercent,
    required this.unitCost,
    required this.totalCost,
  });
}
