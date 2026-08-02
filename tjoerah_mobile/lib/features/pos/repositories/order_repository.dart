import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../providers/cart_provider.dart';

class OrderSyncResult {
  const OrderSyncResult({
    required this.syncedCount,
    required this.pendingCount,
    this.error,
  });

  final int syncedCount;
  final int pendingCount;
  final String? error;

  bool get isComplete => pendingCount == 0;
}

class CreatedOrder {
  const CreatedOrder({
    required this.id,
    required this.receiptNumber,
    required this.createdAt,
    required this.isSynced,
    this.serverId,
    this.status = 'paid',
  });

  final String id;
  final String receiptNumber;
  final DateTime createdAt;
  final bool isSynced;
  final String? serverId;
  final String status;
}

class OrderRepository {
  static const _uuid = Uuid();

  Future<CreatedOrder> createOrder({
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String orderType,
    required String paymentMethod,
    required Map<String, double> paymentBreakdown,
    String? tableId,
    String? tableName,
    String? note,
    String? customerId,
    String? customerName,
    double? amountReceived,
    double change = 0,
    bool isOpenBill = false,
  }) async {
    final orderId = _uuid.v4();
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    final receiptNumber =
        'TJ-${now.year.toString().substring(2)}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final itemPayloads = items
        .map(
          (item) => {
            if (!item.isManual)
              'product_id': int.tryParse(item.productId) ?? item.productId,
            if (item.isManual) 'is_manual': true,
            'snapshot_name': item.name,
            'snapshot_price': item.price,
            'qty': item.quantity,
            'total': item.total,
            if (item.station != null && item.station!.isNotEmpty)
              'station': item.station,
          },
        )
        .toList();

    final parsedCustomerId = int.tryParse(customerId ?? '');
    final payload = <String, dynamic>{
      'outlet_id': await _resolveOutletId(),
      'order_type': orderType,
      'customer_id': ?parsedCustomerId,
      if (tableId != null) 'table_id': int.tryParse(tableId),
      'subtotal': subtotal,
      'discount_total': discount,
      'tax': tax,
      'service_charge': 0,
      'total': total,
      'is_open_bill': isOpenBill,
      if (!isOpenBill) 'payment_method': paymentMethod,
      if (!isOpenBill) 'paymentMethod': paymentMethod,
      'receipt_number': receiptNumber,
      'items': itemPayloads,
      'meta': {
        'client_order_id': orderId,
        if (!isOpenBill) 'payment_breakdown': paymentBreakdown,
        if (isOpenBill) 'server_order_status': 'open',
        if (note != null && note.isNotEmpty) 'note': note,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
        if (customerId != null && customerId.isNotEmpty)
          'customer_local_id': customerId,
        if (tableName != null && tableName.isNotEmpty) 'table_name': tableName,
        'amount_received': ?amountReceived,
        if (change > 0) 'change': change,
      },
      'created_at': timestamp,
    };

    try {
      final response = await ApiClient.post('/orders', payload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = Map<String, dynamic>.from(
          jsonDecode(response.body) as Map,
        );
        final serverOrder = body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : <String, dynamic>{};
        final meta = Map<String, dynamic>.from(payload['meta'] as Map);
        meta['server_order_id'] = serverOrder['id']?.toString();
        meta['server_order_status'] =
            serverOrder['status']?.toString() ?? (isOpenBill ? 'open' : 'paid');
        payload['meta'] = meta;
        await _saveLocal(orderId, payload, timestamp, 'synced');
        if (!isOpenBill) {
          await _recordLocalCustomerVisit(customerId, total, timestamp);
        }
        return CreatedOrder(
          id: orderId,
          receiptNumber: receiptNumber,
          createdAt: now,
          isSynced: true,
          serverId: serverOrder['id']?.toString(),
          status: serverOrder['status']?.toString() ?? 'paid',
        );
      }
      debugPrint(
        'Order API rejected request: ${response.statusCode} '
        '${_responseMessage(response.statusCode, response.body)}',
      );
    } catch (error) {
      debugPrint('Order saved offline: $error');
    }

    await _saveLocal(orderId, payload, timestamp, 'pending');
    if (!isOpenBill) {
      await _recordLocalCustomerVisit(customerId, total, timestamp);
    }
    return CreatedOrder(
      id: orderId,
      receiptNumber: receiptNumber,
      createdAt: now,
      isSynced: false,
      status: isOpenBill ? 'open' : 'paid',
    );
  }

  Future<CreatedOrder> createOpenBill({
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required String orderType,
    String? tableId,
    String? tableName,
    String? note,
    String? customerId,
    String? customerName,
  }) {
    return createOrder(
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      orderType: orderType,
      tableId: tableId,
      tableName: tableName,
      note: note,
      customerId: customerId,
      customerName: customerName,
      paymentMethod: 'open_bill',
      paymentBreakdown: const {},
      isOpenBill: true,
    );
  }

  Future<void> payOpenBill({
    required String serverId,
    required String receiptNumber,
    required String method,
    required Map<String, double> paymentBreakdown,
    double? amountReceived,
    double change = 0,
  }) async {
    final response = await ApiClient.post('/orders/$serverId/pay', {
      'method': method,
      'payment_breakdown': paymentBreakdown,
      'amount_received': amountReceived,
      'change': change,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_responseMessage(response.statusCode, response.body));
    }

    await _markLocalOrderPaid(
      receiptNumber: receiptNumber,
      method: method,
      paymentBreakdown: paymentBreakdown,
      amountReceived: amountReceived,
      change: change,
    );
  }

  Future<int> appendOpenBill({
    required String serverId,
    required String receiptNumber,
    required List<CartItem> items,
  }) async {
    final clientAppendId = _uuid.v4();
    final itemPayloads = items
        .map(
          (item) => <String, dynamic>{
            if (!item.isManual)
              'product_id': int.tryParse(item.productId) ?? item.productId,
            if (item.isManual) 'is_manual': true,
            'snapshot_name': item.name,
            'snapshot_price': item.price,
            'qty': item.quantity,
            'total': item.total,
            if (item.station != null && item.station!.isNotEmpty)
              'station': item.station,
          },
        )
        .toList();
    final response = await ApiClient.post('/orders/$serverId/items', {
      'client_append_id': clientAppendId,
      'items': itemPayloads,
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_responseMessage(response.statusCode, response.body));
    }

    final decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final batch =
        int.tryParse(decoded['submission_batch']?.toString() ?? '') ?? 1;
    final serverOrder = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : <String, dynamic>{};
    await _appendLocalOpenBill(
      receiptNumber: receiptNumber,
      itemPayloads: itemPayloads,
      submissionBatch: batch,
      serverOrder: serverOrder,
    );
    return batch;
  }

  Future<void> _recordLocalCustomerVisit(
    String? customerId,
    double total,
    String timestamp,
  ) async {
    if (customerId == null || customerId.isEmpty) return;

    try {
      final database = await DatabaseHelper.instance.database;
      await database.rawUpdate(
        '''
        UPDATE customers
        SET total_spent = total_spent + ?,
            visit_count = visit_count + 1,
            last_purchase_at = ?,
            updated_at = ?
        WHERE id = ?
        ''',
        [total, timestamp, timestamp, customerId],
      );
    } catch (error) {
      debugPrint('Local customer statistics could not be updated: $error');
    }
  }

  Future<void> _saveLocal(
    String orderId,
    Map<String, dynamic> payload,
    String timestamp,
    String status,
  ) async {
    final database = await DatabaseHelper.instance.database;
    await database.insert('offline_orders', {
      'id': orderId,
      'payload': jsonEncode(payload),
      'created_at': timestamp,
      'status': status,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _markLocalOrderPaid({
    required String receiptNumber,
    required String method,
    required Map<String, double> paymentBreakdown,
    required double? amountReceived,
    required double change,
  }) async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query('offline_orders');
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row['payload']?.toString() ?? '{}') as Map,
      );
      if (payload['receipt_number']?.toString() != receiptNumber) continue;
      final meta = payload['meta'] is Map
          ? Map<String, dynamic>.from(payload['meta'] as Map)
          : <String, dynamic>{};
      meta['server_order_status'] = 'paid';
      meta['payment_breakdown'] = paymentBreakdown;
      meta['amount_received'] = amountReceived;
      meta['change'] = change;
      payload['meta'] = meta;
      payload['payment_method'] = method;
      payload['paymentMethod'] = method;
      payload['is_open_bill'] = false;
      await database.update(
        'offline_orders',
        {'payload': jsonEncode(payload), 'status': 'synced'},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return;
    }
  }

  Future<void> _appendLocalOpenBill({
    required String receiptNumber,
    required List<Map<String, dynamic>> itemPayloads,
    required int submissionBatch,
    required Map<String, dynamic> serverOrder,
  }) async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query('offline_orders');
    final submittedAt = DateTime.now().toIso8601String();
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row['payload']?.toString() ?? '{}') as Map,
      );
      if (payload['receipt_number']?.toString() != receiptNumber) continue;
      final existing = (payload['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      payload['items'] = [
        ...existing,
        ...itemPayloads.map(
          (item) => {
            ...item,
            'submission_batch': submissionBatch,
            'submitted_at': submittedAt,
          },
        ),
      ];
      for (final key in [
        'subtotal',
        'discount_total',
        'tax',
        'tax_rate',
        'service_charge',
        'total',
      ]) {
        if (serverOrder.containsKey(key)) payload[key] = serverOrder[key];
      }
      await database.update(
        'offline_orders',
        {'payload': jsonEncode(payload), 'status': 'synced'},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return;
    }
  }

  Future<OrderSyncResult> syncOfflineOrders() async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query(
      'offline_orders',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );

    var syncedCount = 0;
    String? lastError;
    for (final row in rows) {
      final orderId = row['id'] as String;
      final payload = jsonDecode(row['payload'] as String);
      try {
        final response = await ApiClient.post('/orders', payload);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final body = Map<String, dynamic>.from(
            jsonDecode(response.body) as Map,
          );
          final serverOrder = body['data'] is Map
              ? Map<String, dynamic>.from(body['data'] as Map)
              : <String, dynamic>{};
          final updatedPayload = Map<String, dynamic>.from(payload as Map);
          final meta = updatedPayload['meta'] is Map
              ? Map<String, dynamic>.from(updatedPayload['meta'] as Map)
              : <String, dynamic>{};
          meta['server_order_id'] = serverOrder['id']?.toString();
          meta['server_order_status'] =
              serverOrder['status']?.toString() ?? 'paid';
          updatedPayload['meta'] = meta;
          await database.update(
            'offline_orders',
            {'status': 'synced', 'payload': jsonEncode(updatedPayload)},
            where: 'id = ?',
            whereArgs: [orderId],
          );
          syncedCount++;
        } else {
          lastError = _responseMessage(response.statusCode, response.body);
          debugPrint(
            'Pending order $orderId was rejected: ${response.statusCode} '
            '$lastError',
          );
        }
      } catch (error) {
        lastError = 'Koneksi ke server transaksi belum tersedia.';
        debugPrint('Pending order $orderId sync failed: $error');
      }
    }

    final countRows = await database.rawQuery(
      "SELECT COUNT(*) AS total FROM offline_orders WHERE status = 'pending'",
    );
    final pendingCount = (countRows.first['total'] as num?)?.toInt() ?? 0;
    return OrderSyncResult(
      syncedCount: syncedCount,
      pendingCount: pendingCount,
      error: pendingCount == 0 ? null : lastError,
    );
  }

  Future<int> _resolveOutletId() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('auth_user');
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        final user = Map<String, dynamic>.from(jsonDecode(rawUser) as Map);
        final direct = int.tryParse(user['outlet_id']?.toString() ?? '');
        if (direct != null) return direct;

        final outlets = user['outlets'];
        if (outlets is List && outlets.isNotEmpty && outlets.first is Map) {
          final id = int.tryParse(
            (outlets.first as Map)['id']?.toString() ?? '',
          );
          if (id != null) return id;
        }
      } catch (error) {
        debugPrint('Cached outlet could not be read: $error');
      }
    }
    throw StateError('Outlet aktif belum tersedia untuk transaksi.');
  }

  String _responseMessage(int statusCode, String body) {
    if (statusCode == 401) {
      return 'Sesi masuk sudah berakhir. Silakan masuk kembali.';
    }
    if (statusCode >= 500) {
      return 'Server transaksi sedang bermasalah.';
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return 'Data transaksi ditolak oleh server.';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
