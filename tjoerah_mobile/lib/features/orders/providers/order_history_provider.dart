import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../models/order_history_model.dart';

class OrderHistoryNotifier extends AsyncNotifier<List<OrderHistoryItem>> {
  @override
  Future<List<OrderHistoryItem>> build() => _load();

  Future<List<OrderHistoryItem>> _load() async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query(
      'offline_orders',
      orderBy: 'created_at DESC',
    );
    return rows.map(OrderHistoryItem.fromRow).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }
}

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<OrderHistoryItem>>(
      OrderHistoryNotifier.new,
    );

final customerOrderHistoryProvider = FutureProvider.autoDispose
    .family<List<OrderHistoryItem>, String>((ref, customerId) async {
      final database = await DatabaseHelper.instance.database;
      final customerRows = await database.query(
        'customers',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      final customerName = customerRows.firstOrNull?['name']
          ?.toString()
          .trim()
          .toLowerCase();
      final orderRows = await database.query(
        'offline_orders',
        orderBy: 'created_at DESC',
      );
      final local = orderRows
          .map(OrderHistoryItem.fromRow)
          .where(
            (order) =>
                order.customerId == customerId ||
                (order.customerId == null &&
                    customerName != null &&
                    order.customerName?.trim().toLowerCase() == customerName),
          )
          .toList();

      final remoteId = int.tryParse(customerId);
      if (remoteId == null) return local;

      try {
        final response = await ApiClient.get(
          '/customers/$remoteId/orders?per_page=100',
        );
        if (response.statusCode != 200) return local;

        final decoded = jsonDecode(response.body);
        final rawOrders = decoded is Map ? decoded['data'] as List? ?? [] : [];
        final merged = <String, OrderHistoryItem>{
          for (final order in local) order.receiptNumber: order,
        };
        for (final rawOrder in rawOrders.whereType<Map>()) {
          final order = OrderHistoryItem.fromApi(
            Map<String, dynamic>.from(rawOrder),
          );
          merged[order.receiptNumber] = order;
        }
        final result = merged.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return result;
      } catch (_) {
        return local;
      }
    });
