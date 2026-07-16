import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../models/inventory_models.dart';

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
    final itemsList = await db.query('inventory_items');

    final items = itemsList.map((row) {
      return InventoryItemModel(
        id: int.parse(row['id'].toString()),
        name: row['name'].toString(),
        sku: row['sku']?.toString() ?? '',
        itemType: 'raw_material', // default
        unit: row['unit']?.toString() ?? 'pcs',
        weightedAverageCost:
            double.tryParse(row['weighted_average_cost'].toString()) ?? 0.0,
        minimumStock: 10.0, // default dummy
        currentStock: double.tryParse(row['current_stock'].toString()) ?? 0.0,
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
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadData());
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

  Future<void> _syncOfflineIncidents() async {
    final db = await DatabaseHelper.instance.database;
    final incidents = await db.query(
      'offline_inventory_incidents',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    for (var incident in incidents) {
      final type = incident['type'].toString();
      final payload = jsonDecode(incident['payload'].toString());

      try {
        final endpoint = type == 'spoilage'
            ? '/inventory/wastage'
            : '/inventory/adjustments';
        final response = await ApiClient.post(endpoint, payload);

        if (response.statusCode == 201) {
          await db.delete(
            'offline_inventory_incidents',
            where: 'id = ?',
            whereArgs: [incident['id']],
          );
        }
      } catch (e) {
        // Stop on first failure to keep order
        break;
      }
    }
  }

  Future<void> syncPendingIncidents() => _syncOfflineIncidents();
}

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, InventoryState>(
      () => InventoryNotifier(),
    );
