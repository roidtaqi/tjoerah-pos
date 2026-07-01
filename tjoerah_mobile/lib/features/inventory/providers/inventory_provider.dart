import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../models/inventory_models.dart';

class InventoryProvider extends ChangeNotifier {
  List<InventoryItemModel> _items = [];
  List<StockMovementModel> _movements = [];
  bool _isLoading = false;
  String? _error;

  List<InventoryItemModel> get items => _items;
  List<StockMovementModel> get movements => _movements;
  bool get isLoading => _isLoading;
  String? get error => _error;

  InventoryProvider() {
    loadInventory();
  }

  Future<void> loadInventory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final itemsResponse = await ApiClient.get('/inventory');
      final movementsResponse = await ApiClient.get('/inventory/movements');

      if (itemsResponse.statusCode == 200 && movementsResponse.statusCode == 200) {
        final Map<String, dynamic> itemsData = jsonDecode(itemsResponse.body);
        final List<dynamic> itemsList = itemsData['data'] ?? [];
        _items = itemsList.map((e) => InventoryItemModel.fromJson(e as Map<String, dynamic>)).toList();

        final Map<String, dynamic> movementsData = jsonDecode(movementsResponse.body);
        final List<dynamic> movementsList = movementsData['data'] ?? [];
        _movements = movementsList.map((e) => StockMovementModel.fromJson(e as Map<String, dynamic>)).toList();

        _error = null;
      } else {
        _error = 'Failed to load stock data from server.';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> adjustStock({
    required int itemId,
    required int warehouseId,
    required double qty,
    required String reason,
  }) async {
    try {
      final response = await ApiClient.post('/inventory/adjustments', {
        'inventory_item_id': itemId,
        'warehouse_id': warehouseId,
        'quantity': qty,
        'reason': reason,
      });

      if (response.statusCode == 201) {
        loadInventory();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> logWastage({
    required int itemId,
    required int warehouseId,
    required int outletId,
    required double qty,
    required String reason,
    String wasteType = 'spoilage',
  }) async {
    try {
      final response = await ApiClient.post('/inventory/wastage', {
        'inventory_item_id': itemId,
        'warehouse_id': warehouseId,
        'outlet_id': outletId,
        'quantity': qty,
        'waste_type': wasteType,
        'reason': reason,
      });

      if (response.statusCode == 201) {
        loadInventory();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
