import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../../pos/repositories/order_repository.dart';
import '../../cash/providers/cash_provider.dart';
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
  DateTime? _dateFrom;
  DateTime? _dateTo;

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

  Future<void> refresh({DateTime? dateFrom, DateTime? dateTo}) async {
    if (dateFrom != null && dateTo != null) {
      _dateFrom = _dateOnly(dateFrom);
      _dateTo = _dateOnly(dateTo);
    }
    final local = await _loadLocalForPeriod(
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      includeOpenBills: true,
    );
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(
        await _loadRemote(local, dateFrom: _dateFrom, dateTo: _dateTo),
      );
    } catch (_) {
      state = AsyncValue.data(local);
    }
  }

  Future<List<OrderHistoryItem>> _loadLocalForPeriod({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool includeOpenBills = false,
  }) async {
    final orders = await _loadLocal();
    if (dateFrom == null || dateTo == null) return orders;
    final endExclusive = dateTo.add(const Duration(days: 1));
    return orders.where((order) {
      final createdAt = order.createdAt.toLocal();
      return (includeOpenBills && order.isOpenBill) ||
          (!createdAt.isBefore(dateFrom) && createdAt.isBefore(endExclusive));
    }).toList();
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

  Future<OrderHistoryMutationResult> payOpenBill({
    required OrderHistoryItem order,
    required String method,
    required Map<String, double> paymentBreakdown,
    double? amountReceived,
    double change = 0,
  }) async {
    if (order.serverId == null || order.isPending) {
      return const OrderHistoryMutationResult(
        isSuccess: false,
        message:
            'Sinkronkan open bill terlebih dahulu sebelum menerima pembayaran.',
      );
    }

    try {
      await OrderRepository().payOpenBill(
        serverId: order.serverId!,
        receiptNumber: order.receiptNumber,
        method: method,
        paymentBreakdown: paymentBreakdown,
        amountReceived: amountReceived,
        change: change,
        cashShiftId: ref.read(activeCashShiftIdProvider),
      );
      await refresh();
      return const OrderHistoryMutationResult(
        isSuccess: true,
        message: 'Open bill berhasil dibayar.',
      );
    } catch (error) {
      final message = error.toString().replaceFirst('Bad state: ', '');
      return OrderHistoryMutationResult(
        isSuccess: false,
        message: message.isEmpty
            ? 'Pembayaran open bill belum dapat disimpan.'
            : message,
      );
    }
  }

  Future<OrderHistoryMutationResult> cancelOrder({
    required OrderHistoryItem order,
    required String inventoryOutcome,
    required String reason,
  }) async {
    if (order.serverId == null || order.isPending) {
      return const OrderHistoryMutationResult(
        isSuccess: false,
        message: 'Sinkronkan pesanan terlebih dahulu sebelum membatalkan.',
      );
    }

    try {
      final response = await ApiClient.post('/orders/${order.serverId}/void', {
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
              'Pesanan belum dapat dibatalkan.',
        );
      }

      final serverData = body['data'];
      if (serverData is Map) {
        final rawOrder = Map<String, dynamic>.from(serverData);
        final cancelledOrder = OrderHistoryItem.fromApi(rawOrder);
        _replaceOrder(cancelledOrder);
        try {
          await _cacheServerOrderUpdate(rawOrder, cancelledOrder);
        } catch (_) {
          // The server is authoritative; a later refresh can repair the cache.
        }
      } else {
        await refresh();
      }
      return OrderHistoryMutationResult(
        isSuccess: true,
        message: body['message']?.toString() ?? 'Pesanan berhasil dibatalkan.',
      );
    } catch (_) {
      return const OrderHistoryMutationResult(
        isSuccess: false,
        message:
            'Pesanan belum dapat dibatalkan. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  void _replaceOrder(OrderHistoryItem updated) {
    final current = state.asData?.value ?? const <OrderHistoryItem>[];
    var replaced = false;
    final next = current.map((order) {
      final isMatch =
          (updated.serverId != null && order.serverId == updated.serverId) ||
          order.receiptNumber == updated.receiptNumber;
      if (!isMatch) return order;
      replaced = true;
      return updated;
    }).toList();
    if (!replaced) next.add(updated);
    next.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    state = AsyncValue.data(next);
  }

  Future<void> _cacheServerOrderUpdate(
    Map<String, dynamic> serverData,
    OrderHistoryItem updated,
  ) async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query('offline_orders');
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row['payload']?.toString() ?? '{}') as Map,
      );
      final existingMeta = payload['meta'] is Map
          ? Map<String, dynamic>.from(payload['meta'] as Map)
          : <String, dynamic>{};
      final sameReceipt =
          payload['receipt_number']?.toString() == updated.receiptNumber;
      final sameServerId =
          existingMeta['server_order_id']?.toString() == updated.serverId;
      if (!sameReceipt && !sameServerId) continue;

      final serverMeta = serverData['meta'] is Map
          ? Map<String, dynamic>.from(serverData['meta'] as Map)
          : <String, dynamic>{};
      existingMeta.addAll(serverMeta);
      existingMeta['server_order_id'] = updated.serverId;
      existingMeta['server_order_status'] = updated.orderStatus;
      existingMeta['refunded_amount'] = updated.refundedAmount;
      payload['meta'] = existingMeta;
      for (final key in [
        'subtotal',
        'discount_total',
        'tax',
        'service_charge',
        'total',
      ]) {
        if (serverData.containsKey(key)) payload[key] = serverData[key];
      }
      if (serverData['items'] is List) payload['items'] = serverData['items'];

      await database.update(
        'offline_orders',
        {'payload': jsonEncode(payload), 'status': 'synced'},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return;
    }
  }

  Future<List<OrderHistoryItem>> _loadRemote(
    List<OrderHistoryItem> local, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final query = <String, String>{'per_page': '100'};
    if (dateFrom != null && dateTo != null) {
      query['created_from'] = dateFrom.toUtc().toIso8601String();
      query['created_to'] = dateTo
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String();
      query['include_open'] = '1';
    }
    final response = await ApiClient.get(
      '/orders?${Uri(queryParameters: query).query}',
    );
    if (response.statusCode != 200) throw Exception(response.body);
    final decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final rows = decoded['data'] as List? ?? const [];
    final merged = <String, OrderHistoryItem>{
      for (final order in local.where((order) => order.isPending))
        order.receiptNumber: order,
    };
    for (final row in rows.whereType<Map>()) {
      final rawOrder = Map<String, dynamic>.from(row);
      final order = OrderHistoryItem.fromApi(rawOrder);
      merged[order.receiptNumber] = order;
      if (order.isVoided) {
        try {
          await _cacheServerOrderUpdate(rawOrder, order);
        } catch (_) {
          // Keep remote history usable even when the local cache cannot update.
        }
      }
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

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

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
