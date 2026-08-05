import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sync_service.dart';
import '../models/inventory_models.dart';

class InventoryMutationResult {
  const InventoryMutationResult._(this.isSuccess, this.message);

  const InventoryMutationResult.success(String message) : this._(true, message);

  const InventoryMutationResult.failure(String message)
    : this._(false, message);

  final bool isSuccess;
  final String message;
}

class InventoryState {
  final List<InventoryItemModel> items;
  final List<StockMovementModel> movements;

  InventoryState({this.items = const [], this.movements = const []});
}

class InventoryNotifier extends AsyncNotifier<InventoryState> {
  @override
  Future<InventoryState> build() async {
    return _loadData();
  }

  Future<InventoryState> _loadData() async {
    final db = await DatabaseHelper.instance.database;
    final itemsList = await db.query(
      'inventory_items',
      orderBy: 'name COLLATE NOCASE',
    );

    final items = itemsList.map((row) {
      return InventoryItemModel(
        id: int.parse(row['id'].toString()),
        name: row['name'].toString(),
        sku: row['sku']?.toString() ?? '',
        itemType: row['item_type']?.toString() ?? 'raw_material',
        unit: row['unit']?.toString() ?? 'pcs',
        weightedAverageCost:
            double.tryParse(row['weighted_average_cost'].toString()) ?? 0.0,
        minimumStock: double.tryParse(row['minimum_stock'].toString()) ?? 0.0,
        currentStock: double.tryParse(row['current_stock'].toString()) ?? 0.0,
        isActive: row['is_active'] == null || row['is_active'] == 1,
      );
    }).toList();

    List<StockMovementModel> movements = [];
    try {
      final movementsResponse = await ApiClient.get('/inventory/movements');
      if (movementsResponse.statusCode == 200) {
        final Map<String, dynamic> movementsData = jsonDecode(
          movementsResponse.body,
        );
        final List<dynamic> movementsList = movementsData['data'] ?? [];
        movements = movementsList
            .map((e) => StockMovementModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Offline, no movements fetched
    }

    return InventoryState(items: items, movements: movements);
  }

  Future<void> refresh() async {
    final previous = state.asData?.value;
    state = const AsyncValue.loading();
    final synced = await SyncService.syncInventory();
    if (!synced && previous != null) {
      state = AsyncValue.data(previous);
      return;
    }
    state = await AsyncValue.guard(() => _loadData());
  }

  Future<InventoryMutationResult> createItem(InventoryItemDraft draft) async {
    try {
      final response = await ApiClient.post('/inventory/items', draft.toJson());
      if (response.statusCode != 201) {
        return InventoryMutationResult.failure(_responseMessage(response.body));
      }
      await _cacheItem(response.body);
      final synced = await _syncAfterMutation();
      return InventoryMutationResult.success(
        synced
            ? '${draft.name.trim()} berhasil ditambahkan.'
            : '${draft.name.trim()} tersimpan dan siap dipakai pada resep.',
      );
    } catch (_) {
      return const InventoryMutationResult.failure(
        'Bahan belum dapat ditambahkan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<InventoryMutationResult> updateItem(
    InventoryItemModel item,
    InventoryItemDraft draft,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/inventory/items/${item.id}',
        draft.toJson(),
      );
      if (response.statusCode != 200) {
        return InventoryMutationResult.failure(_responseMessage(response.body));
      }
      await _cacheItem(response.body);
      final synced = await _syncAfterMutation();
      return InventoryMutationResult.success(
        synced
            ? '${draft.name.trim()} berhasil diperbarui.'
            : '${draft.name.trim()} diperbarui pada perangkat ini.',
      );
    } catch (_) {
      return const InventoryMutationResult.failure(
        'Perubahan bahan belum dapat disimpan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<bool> adjustStock({
    required int itemId,
    required double qty,
    required String reason,
    required String type, // 'adjustment' or 'spoilage'
  }) async {
    final db = await DatabaseHelper.instance.database;

    // Save to offline incidents queue
    final incidentId = DateTime.now().millisecondsSinceEpoch.toString();
    await db.insert('offline_inventory_incidents', {
      'id': incidentId,
      'type': type,
      'payload': jsonEncode({
        'inventory_item_id': itemId,
        'warehouse_id': 1, // Default warehouse
        'quantity': qty,
        'reason': reason,
      }),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });

    // Locally update current stock
    final currentItem = state.value?.items.firstWhere((e) => e.id == itemId);
    if (currentItem != null) {
      // If adjustment, qty is delta. If spoilage, qty is absolute positive but reduces stock (delta is -qty)
      final delta = type == 'spoilage' ? -qty.abs() : qty;
      final newStock = currentItem.currentStock + delta;

      await db.update(
        'inventory_items',
        {'current_stock': newStock},
        where: 'id = ?',
        whereArgs: [itemId.toString()],
      );
    }

    // Refresh state
    await refresh();

    // Attempt sync immediately (fire and forget)
    _syncOfflineIncidents();

    return true;
  }

  Future<String?> _syncOfflineIncidents() async {
    final db = await DatabaseHelper.instance.database;
    final incidents = await db.query(
      'offline_inventory_incidents',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    String? lastError;
    for (var incident in incidents) {
      final type = incident['type'].toString();
      final payload = jsonDecode(incident['payload'].toString());

      try {
        final endpoint = type == 'spoilage'
            ? '/inventory/wastage'
            : '/inventory/adjustments';
        final response = await ApiClient.post(endpoint, payload);

        if (response.statusCode == 200 || response.statusCode == 201) {
          await db.delete(
            'offline_inventory_incidents',
            where: 'id = ?',
            whereArgs: [incident['id']],
          );
        } else {
          lastError = 'Inventori tertahan: ${_responseMessage(response.body)}';
          break;
        }
      } catch (_) {
        lastError = 'Inventori tertahan karena server belum dapat dihubungi.';
        break;
      }
    }
    return lastError;
  }

  Future<String?> syncPendingIncidents() => _syncOfflineIncidents();

  Future<void> _cacheItem(String responseBody) async {
    final item = Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'inventory_items',
      columns: ['current_stock'],
      where: 'id = ?',
      whereArgs: [item['id'].toString()],
      limit: 1,
    );
    await db.insert('inventory_items', {
      'id': item['id'].toString(),
      'name': item['name'],
      'sku': item['sku'],
      'item_type': item['item_type'] ?? 'raw_material',
      'unit': item['unit'] ?? 'pcs',
      'current_stock':
          item['current_stock'] ??
          (existing.isEmpty ? 0.0 : existing.first['current_stock']),
      'weighted_average_cost': item['weighted_average_cost'] ?? 0.0,
      'minimum_stock': item['minimum_stock'] ?? 0.0,
      'is_active': item['is_active'] == false || item['is_active'] == 0 ? 0 : 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      // The fallback below is clearer than a malformed server response.
    }
    return 'Permintaan belum dapat diproses. Coba lagi.';
  }
}

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, InventoryState>(
      () => InventoryNotifier(),
    );
