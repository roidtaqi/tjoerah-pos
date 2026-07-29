class RecipeModel {
  const RecipeModel({
    required this.id,
    this.productId,
    this.productName,
    required this.name,
    this.status = 'draft',
    this.activeVersion = 1,
    required this.currentCost,
    required this.yieldQuantity,
    this.yieldUnit,
    this.items = const [],
    this.versions = const [],
  });

  final String id;
  final String? productId;
  final String? productName;
  final String name;
  final String status;
  final int activeVersion;
  final double currentCost;
  final double yieldQuantity;
  final String? yieldUnit;
  final List<RecipeItemModel> items;
  final List<RecipeVersionModel> versions;

  double get totalBatchCost => currentCost * yieldQuantity;
}

class RecipeItemModel {
  const RecipeItemModel({
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

  final String id;
  final String recipeId;
  final String? inventoryItemId;
  final String? inventoryItemName;
  final double quantity;
  final String? unit;
  final double wastePercent;
  final double unitCost;
  final double totalCost;
}

class RecipeVersionModel {
  const RecipeVersionModel({
    required this.id,
    required this.version,
    required this.totalCost,
    required this.status,
    this.effectiveAt,
  });

  final String id;
  final int version;
  final double totalCost;
  final String status;
  final DateTime? effectiveAt;
}

class RecipeProductOption {
  const RecipeProductOption({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;
}

class RecipeIngredientOption {
  const RecipeIngredientOption({
    required this.id,
    required this.name,
    this.sku,
    required this.unit,
    required this.unitCost,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? sku;
  final String unit;
  final double unitCost;
  final bool isActive;
}

class RecipeEditorOptions {
  const RecipeEditorOptions({
    required this.products,
    required this.ingredients,
  });

  final List<RecipeProductOption> products;
  final List<RecipeIngredientOption> ingredients;
}

class RecipeDraft {
  const RecipeDraft({
    required this.name,
    this.productId,
    required this.status,
    required this.yieldQuantity,
    required this.yieldUnit,
    required this.items,
  });

  factory RecipeDraft.fromRecipe(RecipeModel recipe, {bool duplicate = false}) {
    return RecipeDraft(
      name: duplicate ? 'Salinan ${recipe.name}' : recipe.name,
      productId: duplicate ? null : recipe.productId,
      status: duplicate ? 'draft' : recipe.status,
      yieldQuantity: recipe.yieldQuantity,
      yieldUnit: recipe.yieldUnit ?? 'porsi',
      items: recipe.items
          .where((item) => item.inventoryItemId != null)
          .map(
            (item) => RecipeIngredientDraft(
              inventoryItemId: item.inventoryItemId!,
              quantity: item.quantity,
              wastePercent: item.wastePercent,
            ),
          )
          .toList(),
    );
  }

  final String name;
  final String? productId;
  final String status;
  final double yieldQuantity;
  final String yieldUnit;
  final List<RecipeIngredientDraft> items;

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'product_id': productId,
      'status': status,
      'yield_quantity': yieldQuantity,
      'yield_unit': yieldUnit.trim(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class RecipeIngredientDraft {
  const RecipeIngredientDraft({
    required this.inventoryItemId,
    required this.quantity,
    required this.wastePercent,
  });

  final String inventoryItemId;
  final double quantity;
  final double wastePercent;

  Map<String, dynamic> toJson() {
    return {
      'inventory_item_id': int.tryParse(inventoryItemId) ?? inventoryItemId,
      'quantity': quantity,
      'waste_percent': wastePercent,
    };
  }
}
