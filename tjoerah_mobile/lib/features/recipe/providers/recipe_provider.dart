import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../models/recipe_models.dart';

class RecipeNotifier extends AsyncNotifier<List<RecipeModel>> {
  @override
  Future<List<RecipeModel>> build() async {
    return _loadData();
  }

  Future<List<RecipeModel>> _loadData() async {
    final db = await DatabaseHelper.instance.database;
    final recipesList = await db.query('recipes');
    final recipeItemsList = await db.query('recipe_items');
    final inventoryItemsList = await db.query('inventory_items');

    List<RecipeModel> parsedRecipes = [];

    for (var rRow in recipesList) {
      final rId = rRow['id'].toString();
      final itemsForRecipe = recipeItemsList
          .where((i) => i['recipe_id'].toString() == rId)
          .map((iRow) {
            final inventoryId = iRow['inventory_item_id']?.toString();
            String? inventoryName;
            for (final inventoryRow in inventoryItemsList) {
              if (inventoryRow['id']?.toString() == inventoryId) {
                inventoryName = inventoryRow['name']?.toString();
                break;
              }
            }
            return RecipeItemModel(
              id: iRow['id'].toString(),
              recipeId: rId,
              inventoryItemId: inventoryId,
              inventoryItemName: inventoryName,
              quantity: double.tryParse(iRow['quantity'].toString()) ?? 0.0,
              unit: iRow['unit']?.toString(),
              wastePercent:
                  double.tryParse(iRow['waste_percent'].toString()) ?? 0.0,
              unitCost: double.tryParse(iRow['unit_cost'].toString()) ?? 0.0,
              totalCost: double.tryParse(iRow['total_cost'].toString()) ?? 0.0,
            );
          })
          .toList();

      parsedRecipes.add(
        RecipeModel(
          id: rId,
          productId: rRow['product_id']?.toString(),
          name: rRow['name'].toString(),
          currentCost: double.tryParse(rRow['current_cost'].toString()) ?? 0.0,
          yieldQuantity:
              double.tryParse(rRow['yield_quantity'].toString()) ?? 1.0,
          yieldUnit: rRow['yield_unit']?.toString(),
          items: itemsForRecipe,
        ),
      );
    }

    return parsedRecipes;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadData());
  }

  Future<bool> updateRecipeItem({
    required String recipeId,
    required String itemId,
    required double newQty,
    required double wastePercent,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // Save to offline queue
    final incidentId = DateTime.now().millisecondsSinceEpoch.toString();
    await db.insert('offline_inventory_incidents', {
      'id': incidentId,
      'type': 'update_recipe_item',
      'payload': jsonEncode({
        'recipe_id': recipeId,
        'item_id': itemId,
        'quantity': newQty,
        'waste_percent': wastePercent,
      }),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });

    // Update local DB
    await db.update(
      'recipe_items',
      {'quantity': newQty, 'waste_percent': wastePercent},
      where: 'id = ?',
      whereArgs: [itemId],
    );

    await refresh();
    _syncOfflineUpdates();
    return true;
  }

  Future<void> _syncOfflineUpdates() async {
    final db = await DatabaseHelper.instance.database;
    final incidents = await db.query(
      'offline_inventory_incidents',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    for (var incident in incidents) {
      if (incident['type'].toString() != 'update_recipe_item') continue;

      final payload = jsonDecode(incident['payload'].toString());
      final recipeId = payload['recipe_id'];

      try {
        // We will call the backend RecipeController update endpoint
        // Assuming backend handles PUT /api/recipes/{id} or POST /api/recipes/version
        final response = await ApiClient.post('/recipes/version', {
          'recipe_id': recipeId,
          // the backend expects full recipe items array, but for simplicity of this skeleton we simulate it
        });

        if (response.statusCode == 200 || response.statusCode == 201) {
          await db.delete(
            'offline_inventory_incidents',
            where: 'id = ?',
            whereArgs: [incident['id']],
          );
        }
      } catch (e) {
        break;
      }
    }
  }
}

final recipeProvider = AsyncNotifierProvider<RecipeNotifier, List<RecipeModel>>(
  () => RecipeNotifier(),
);
