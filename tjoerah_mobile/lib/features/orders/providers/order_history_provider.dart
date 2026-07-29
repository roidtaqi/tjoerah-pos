import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../models/order_history_model.dart';

class OrderHistoryMutationResult {
  const OrderHistoryMutationResult({
    required this.isSuccess,
    required this.message,
  });

  final bool isSuccess;
  final String message;
}

class OrderHistoryNotifier extends AsyncNotifier<List<OrderHistoryItem>> {
  @override
  Future<List<OrderHistoryItem>> build() => _loadLocal();

  Future<List<OrderHistoryItem>> _loadLocal() async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query(
      'offline_orders',
      orderBy: 'created_at DESC',
    );
    return rows.map(OrderHistoryItem.fromRow).toList();
  }

  Future<void> refresh() async {
    final local = state.asData?.value ?? await _loadLocal();
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _loadRemote(local));
    } catch (_) {
      state = AsyncValue.data(local);
    }
  }

  Future<OrderHistoryMutationResult> refundOrder({
    required OrderHistoryItem order,
    required OrderHistoryLine item,
    required int quantity,
    required double amount,
    required String inventoryOutcome,
    required String reason,
  }) async {
    if (order.serverId == null || item.id == null) {
      return const OrderHistoryMutationResult(
        isSuccess: false,
        message: 'Muat ulang riwayat dari server sebelum memproses refund.',
      );
    }

    try {
      final response =
          await ApiClient.post('/orders/${order.serverId}/refund', {
            'order_item_id': item.id,
            'quantity': quantity,
            'amount': amount,
            'type': amount >= order.total - order.refundedAmount
                ? 'full'
                : 'partial',
            'inventory_outcome': inventoryOutcome,
            'reason': reason.trim(),
          });
      final decoded = jsonDecode(response.body);
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode != 201) {
        return OrderHistoryMutationResult(
          isSuccess: false,
          message:
              _firstError(body) ??
              body['message']?.toString() ??
              'Refund belum dapat diproses.',
        );
      }
      await refresh();
      return OrderHistoryMutationResult(
        isSuccess: true,
        message: body['message']?.toString() ?? 'Refund berhasil dicatat.',
      );
    } catch (_) {
      return const OrderHistoryMutationResult(
        isSuccess: false,
        message: 'Refund belum dapat diproses. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  Future<List<OrderHistoryItem>> _loadRemote(
    List<OrderHistoryItem> local,
  ) async {
    final response = await ApiClient.get('/orders?per_page=100');
    if (response.statusCode != 200) throw Exception(response.body);
    final decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final rows = decoded['data'] as List? ?? const [];
    final merged = <String, OrderHistoryItem>{
      for (final order in local.where((order) => order.isPending))
        order.receiptNumber: order,
    };
    for (final row in rows.whereType<Map>()) {
      final order = OrderHistoryItem.fromApi(Map<String, dynamic>.from(row));
      merged[order.receiptNumber] = order;
    }
    final orders = merged.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return orders;
  }
}

String? _firstError(Map<String, dynamic> body) {
  final errors = body['errors'];
  if (errors is! Map) return null;
  for (final messages in errors.values) {
    if (messages is List && messages.isNotEmpty) {
      return messages.first.toString();
    }
  }
  return null;
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
