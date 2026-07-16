import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_client.dart';
import '../database/database_helper.dart';

class SyncService {
  static Future<bool> syncCatalog() async {
    try {
      final response = await ApiClient.get('/catalog/sync');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final categories = data['categories'] as List;
        final products = data['products'] as List;

        final db = await DatabaseHelper.instance.database;

        // Use transaction for atomic sync
        await db.transaction((txn) async {
          // Clear old data
          await txn.delete('products');
          await txn.delete('categories');

          // Insert categories
          for (var cat in categories) {
            await txn.insert('categories', {
              'id': cat['id'],
              'name': cat['name'],
              'sort_order': cat['sort_order'] ?? 0,
            });
          }

          // Insert products
          for (var prod in products) {
            await txn.insert('products', {
              'id': prod['id'],
              'category_id': prod['category_id'],
              'name': prod['name'],
              'sku': prod['sku'],
              'price': prod['base_price'] ?? 0.0,
              'station': prod['station'],
              'is_active': (prod['is_active'] == 1 || prod['is_active'] == true)
                  ? 1
                  : 0,
            });
          }
        });

        debugPrint(
          'Catalog synced successfully: ${categories.length} categories, ${products.length} products',
        );
        return true;
      } else {
        debugPrint('Catalog sync failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Error syncing catalog: $e');
      return false;
    }
  }

  static Future<bool> syncInventory() async {
    try {
      final inventoryResponse = await ApiClient.get('/inventory');
      final recipeResponse = await ApiClient.get('/recipes');

      if (inventoryResponse.statusCode == 200 &&
          recipeResponse.statusCode == 200) {
        final inventoryData = jsonDecode(inventoryResponse.body);
        final recipeData = jsonDecode(recipeResponse.body);

        final items = inventoryData['data'] as List;
        final recipes = recipeData['data'] as List;

        final db = await DatabaseHelper.instance.database;

        await db.transaction((txn) async {
          // Clear old inventory/recipe data
          await txn.delete('inventory_items');
          await txn.delete('recipes');
          await txn.delete('recipe_items');

          // Insert inventory items
          for (var item in items) {
            await txn.insert('inventory_items', {
              'id': item['id'].toString(),
              'name': item['name'],
              'sku': item['sku'],
              'unit': item['unit'],
              'current_stock': item['current_stock'] ?? 0.0,
              'weighted_average_cost': item['weighted_average_cost'] ?? 0.0,
              'is_active': (item['is_active'] == 1 || item['is_active'] == true)
                  ? 1
                  : 0,
            });
          }

          // Insert recipes and recipe_items
          for (var recipe in recipes) {
            final recipeId = recipe['id'].toString();
            await txn.insert('recipes', {
              'id': recipeId,
              'product_id': recipe['product_id']?.toString(),
              'name': recipe['name'],
              'current_cost': recipe['current_cost'] ?? 0.0,
              'yield_quantity': recipe['yield_quantity'] ?? 1.0,
              'yield_unit': recipe['yield_unit'],
              'is_synced': 1,
            });

            final recipeItems = recipe['items'] as List? ?? [];
            for (var rItem in recipeItems) {
              await txn.insert('recipe_items', {
                'id': rItem['id'].toString(),
                'recipe_id': recipeId,
                'inventory_item_id': rItem['inventory_item_id']?.toString(),
                'child_recipe_id': rItem['child_recipe_id']?.toString(),
                'quantity': rItem['quantity'] ?? 0.0,
                'unit': rItem['unit'],
                'waste_percent': rItem['waste_percent'] ?? 0.0,
                'unit_cost': rItem['unit_cost'] ?? 0.0,
                'total_cost': rItem['total_cost'] ?? 0.0,
              });
            }
          }
        });

        debugPrint('Inventory synced successfully');
        return true;
      } else {
        debugPrint('Inventory sync failed');
        return false;
      }
    } catch (e) {
      debugPrint('Error syncing inventory: $e');
      return false;
    }
  }

  static Future<bool> syncTables() async {
    try {
      final floorsResponse = await ApiClient.get('/floors');
      final tablesResponse = await ApiClient.get('/tables');

      if (floorsResponse.statusCode == 200 &&
          tablesResponse.statusCode == 200) {
        final floorsData = jsonDecode(floorsResponse.body);
        final tablesData = jsonDecode(tablesResponse.body);

        final floors = floorsData['data'] as List;
        final tables = tablesData['data'] as List;

        final db = await DatabaseHelper.instance.database;

        await db.transaction((txn) async {
          // Clear old table data
          await txn.delete('floors');
          await txn.delete('dining_tables');
          // Note: table_sessions should ideally not be deleted completely if we handle offline sessions,
          // but for this sync we focus on structure. We will keep open sessions intact or sync them differently.
          // For now, let's just clear and replace structure.

          for (var floor in floors) {
            await txn.insert('floors', {
              'id': floor['id'].toString(),
              'name': floor['name'],
              'sort_order': floor['sort_order'] ?? 0,
            });
          }

          for (var table in tables) {
            await txn.insert('dining_tables', {
              'id': table['id'].toString(),
              'floor_id': table['floor_id']?.toString(),
              'name': table['name'],
              'capacity': table['capacity'] ?? 1,
              'status': table['status'] ?? 'available',
              'position_x':
                  double.tryParse(table['position_x']?.toString() ?? '0') ??
                  0.0,
              'position_y':
                  double.tryParse(table['position_y']?.toString() ?? '0') ??
                  0.0,
            });
          }
        });

        debugPrint('Tables synced successfully');
        return true;
      } else {
        debugPrint('Tables sync failed');
        return false;
      }
    } catch (e) {
      debugPrint('Error syncing tables: $e');
      return false;
    }
  }
}
