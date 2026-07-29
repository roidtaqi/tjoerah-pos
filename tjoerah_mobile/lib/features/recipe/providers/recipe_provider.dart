import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sync_service.dart';
import '../models/recipe_models.dart';

class RecipeMutationResult {
  const RecipeMutationResult._(this.isSuccess, this.message);

  const RecipeMutationResult.success(String message) : this._(true, message);

  const RecipeMutationResult.failure(String message) : this._(false, message);

  final bool isSuccess;
  final String message;
}

class RecipeNotifier extends AsyncNotifier<List<RecipeModel>> {
  @override
  Future<List<RecipeModel>> build() => _loadData();

  Future<List<RecipeModel>> _loadData() async {
    final db = await DatabaseHelper.instance.database;
    final results = await Future.wait([
      db.query('recipes', orderBy: 'name COLLATE NOCASE'),
      db.query('recipe_items'),
      db.query('recipe_versions', orderBy: 'version DESC'),
      db.query('inventory_items'),
      db.query('products'),
    ]);
    final recipesList = results[0];
    final recipeItemsList = results[1];
    final recipeVersionsList = results[2];
    final inventoryItemsList = results[3];
    final productsList = results[4];
    final inventoryNames = {
      for (final row in inventoryItemsList)
        row['id'].toString(): row['name']?.toString(),
    };
    final productNames = {
      for (final row in productsList)
        row['id'].toString(): row['name']?.toString(),
    };

    return recipesList.map((row) {
      final recipeId = row['id'].toString();
      final items = recipeItemsList
          .where((item) => item['recipe_id'].toString() == recipeId)
          .map(
            (item) => RecipeItemModel(
              id: item['id'].toString(),
              recipeId: recipeId,
              inventoryItemId: item['inventory_item_id']?.toString(),
              inventoryItemName:
                  inventoryNames[item['inventory_item_id']?.toString()],
              quantity: _asDouble(item['quantity']),
              unit: item['unit']?.toString(),
              wastePercent: _asDouble(item['waste_percent']),
              unitCost: _asDouble(item['unit_cost']),
              totalCost: _asDouble(item['total_cost']),
            ),
          )
          .toList();
      final versions = recipeVersionsList
          .where((version) => version['recipe_id'].toString() == recipeId)
          .map(
            (version) => RecipeVersionModel(
              id: version['id'].toString(),
              version: _asInt(version['version'], fallback: 1),
              totalCost: _asDouble(version['total_cost']),
              status: version['status']?.toString() ?? 'draft',
              effectiveAt: DateTime.tryParse(
                version['effective_at']?.toString() ?? '',
              ),
            ),
          )
          .toList();
      final productId = row['product_id']?.toString();

      return RecipeModel(
        id: recipeId,
        productId: productId,
        productName: productNames[productId],
        name: row['name']?.toString() ?? '',
        status: row['status']?.toString() ?? 'draft',
        activeVersion: _asInt(row['active_version'], fallback: 1),
        currentCost: _asDouble(row['current_cost']),
        yieldQuantity: _asDouble(row['yield_quantity'], fallback: 1),
        yieldUnit: row['yield_unit']?.toString(),
        items: items,
        versions: versions,
      );
    }).toList();
  }

  Future<void> refresh() async {
    final previous = state.asData?.value;
    state = const AsyncValue.loading();
    final synced = await SyncService.syncInventory();
    if (!synced && previous != null) {
      state = AsyncValue.data(previous);
      return;
    }
    state = await AsyncValue.guard(_loadData);
  }

  Future<RecipeEditorOptions> loadEditorOptions() async {
    var options = await _loadEditorOptions();
    if (options.products.isEmpty || options.ingredients.isEmpty) {
      await Future.wait([
        SyncService.syncCatalog(),
        SyncService.syncInventory(),
      ]);
      options = await _loadEditorOptions();
    }
    return options;
  }

  Future<RecipeMutationResult> createRecipe(RecipeDraft draft) async {
    try {
      final response = await ApiClient.post('/recipes', draft.toJson());
      if (response.statusCode != 201) {
        return RecipeMutationResult.failure(_responseMessage(response.body));
      }
      final synced = await _syncAfterMutation();
      return RecipeMutationResult.success(
        synced
            ? '${draft.name} berhasil ditambahkan.'
            : '${draft.name} tersimpan. Muat ulang saat koneksi stabil.',
      );
    } catch (_) {
      return const RecipeMutationResult.failure(
        'Resep belum dapat ditambahkan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<RecipeMutationResult> updateRecipe(
    RecipeModel recipe,
    RecipeDraft draft,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/recipes/${recipe.id}',
        draft.toJson(),
      );
      if (response.statusCode != 200) {
        return RecipeMutationResult.failure(_responseMessage(response.body));
      }
      final synced = await _syncAfterMutation();
      return RecipeMutationResult.success(
        synced
            ? '${draft.name} diperbarui sebagai versi ${recipe.activeVersion + 1}.'
            : '${draft.name} diperbarui. Muat ulang saat koneksi stabil.',
      );
    } catch (_) {
      return const RecipeMutationResult.failure(
        'Perubahan resep belum dapat disimpan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<RecipeMutationResult> deleteRecipe(RecipeModel recipe) async {
    try {
      final response = await ApiClient.delete('/recipes/${recipe.id}');
      if (response.statusCode != 204) {
        return RecipeMutationResult.failure(_responseMessage(response.body));
      }
      final synced = await _syncAfterMutation();
      return RecipeMutationResult.success(
        synced
            ? '${recipe.name} berhasil dihapus.'
            : '${recipe.name} dihapus. Muat ulang saat koneksi stabil.',
      );
    } catch (_) {
      return const RecipeMutationResult.failure(
        'Resep belum dapat dihapus. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<RecipeEditorOptions> _loadEditorOptions() async {
    final db = await DatabaseHelper.instance.database;
    final results = await Future.wait([
      db.query('products', orderBy: 'name COLLATE NOCASE'),
      db.query('inventory_items', orderBy: 'name COLLATE NOCASE'),
    ]);

    return RecipeEditorOptions(
      products: results[0]
          .map(
            (row) => RecipeProductOption(
              id: row['id'].toString(),
              name: row['name']?.toString() ?? '',
              isActive: _asBool(row['is_active'], fallback: true),
            ),
          )
          .toList(),
      ingredients: results[1]
          .map(
            (row) => RecipeIngredientOption(
              id: row['id'].toString(),
              name: row['name']?.toString() ?? '',
              sku: row['sku']?.toString(),
              unit: row['unit']?.toString() ?? 'pcs',
              unitCost: _asDouble(row['weighted_average_cost']),
              isActive: _asBool(row['is_active'], fallback: true),
            ),
          )
          .toList(),
    );
  }

  Future<bool> _syncAfterMutation() async {
    final synced = await SyncService.syncInventory();
    state = AsyncValue.data(await _loadData());
    return synced;
  }

  String _responseMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final messages in errors.values) {
            if (messages is List && messages.isNotEmpty) {
              return messages.first.toString();
            }
          }
        }
        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }
      }
    } catch (_) {
      // A concise fallback is clearer than an HTML or malformed response.
    }
    return 'Permintaan belum dapat diproses. Coba lagi.';
  }
}

double _asDouble(dynamic value, {double fallback = 0}) {
  return value is num
      ? value.toDouble()
      : double.tryParse('$value') ?? fallback;
}

int _asInt(dynamic value, {required int fallback}) {
  return value is int ? value : int.tryParse('$value') ?? fallback;
}

bool _asBool(dynamic value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains(value.toString().toLowerCase());
}

final recipeProvider = AsyncNotifierProvider<RecipeNotifier, List<RecipeModel>>(
  RecipeNotifier.new,
);
