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
  });

  final String id;
  final String receiptNumber;
  final DateTime createdAt;
  final bool isSynced;
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
    String? customerName,
    double? amountReceived,
    double change = 0,
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
            'product_id': int.tryParse(item.productId) ?? item.productId,
            'snapshot_name': item.name,
            'snapshot_price': item.price,
            'qty': item.quantity,
            'total': item.total,
            if (item.station != null && item.station!.isNotEmpty)
              'station': item.station,
          },
        )
        .toList();

    final payload = <String, dynamic>{
      'outlet_id': await _resolveOutletId(),
      'order_type': orderType,
      if (tableId != null) 'table_id': int.tryParse(tableId),
      'subtotal': subtotal,
      'discount_total': discount,
      'tax': tax,
      'service_charge': 0,
      'total': total,
      'payment_method': paymentMethod,
      'paymentMethod': paymentMethod,
      'receipt_number': receiptNumber,
      'items': itemPayloads,
      'meta': {
        'client_order_id': orderId,
        'payment_breakdown': paymentBreakdown,
        if (note != null && note.isNotEmpty) 'note': note,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
        if (tableName != null && tableName.isNotEmpty) 'table_name': tableName,
        'amount_received': ?amountReceived,
        if (change > 0) 'change': change,
      },
      'created_at': timestamp,
    };

    try {
      final response = await ApiClient.post('/orders', payload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _saveLocal(orderId, payload, timestamp, 'synced');
        return CreatedOrder(
          id: orderId,
          receiptNumber: receiptNumber,
          createdAt: now,
          isSynced: true,
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
    return CreatedOrder(
      id: orderId,
      receiptNumber: receiptNumber,
      createdAt: now,
      isSynced: false,
    );
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
          await database.update(
            'offline_orders',
            {'status': 'synced'},
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
