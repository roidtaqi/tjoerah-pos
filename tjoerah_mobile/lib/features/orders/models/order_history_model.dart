import 'dart:convert';

import '../../../core/printer/print_job.dart';

class OrderHistoryItem {
  const OrderHistoryItem({
    required this.id,
    required this.receiptNumber,
    required this.orderType,
    required this.paymentMethod,
    required this.total,
    required this.createdAt,
    required this.syncStatus,
    required this.items,
    required this.paymentBreakdown,
    this.subtotal = 0,
    this.discount = 0,
    this.tax = 0,
    this.amountReceived,
    this.change = 0,
    this.customerId,
    this.customerName,
    this.tableId,
    this.tableName,
    this.note,
  });

  final String id;
  final String receiptNumber;
  final String orderType;
  final String paymentMethod;
  final double total;
  final DateTime createdAt;
  final String syncStatus;
  final List<OrderHistoryLine> items;
  final Map<String, double> paymentBreakdown;
  final double subtotal;
  final double discount;
  final double tax;
  final double? amountReceived;
  final double change;
  final String? customerId;
  final String? customerName;
  final String? tableId;
  final String? tableName;
  final String? note;

  bool get isPending => syncStatus == 'pending';
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  TransactionPrintData toPrintData() {
    final calculatedSubtotal = subtotal > 0
        ? subtotal
        : items.fold<double>(0, (sum, item) => sum + item.total);
    return TransactionPrintData(
      orderId: id,
      receiptNumber: receiptNumber,
      createdAt: createdAt,
      orderTypeLabel: switch (orderType) {
        'dine_in' => 'Makan di tempat',
        'delivery' => 'Pesan antar',
        _ => 'Bawa pulang',
      },
      paymentMethod: paymentMethod,
      paymentBreakdown: paymentBreakdown,
      items: items
          .map(
            (item) => PrintOrderItem(
              name: item.name,
              quantity: item.quantity,
              unitPrice: item.price,
              station: item.station,
            ),
          )
          .toList(),
      subtotal: calculatedSubtotal,
      discount: discount,
      tax: tax,
      total: total,
      isSynced: !isPending,
      isReprint: true,
      tableName: tableName ?? (tableId == null ? null : 'Meja $tableId'),
      customerName: customerName,
      note: note,
      amountReceived: amountReceived,
      change: change,
    );
  }

  factory OrderHistoryItem.fromRow(Map<String, Object?> row) {
    final payload = Map<String, dynamic>.from(
      jsonDecode(row['payload']?.toString() ?? '{}') as Map,
    );
    final meta = payload['meta'] is Map
        ? Map<String, dynamic>.from(payload['meta'] as Map)
        : <String, dynamic>{};
    final rawItems = payload['items'] is List ? payload['items'] as List : [];
    final rawPayments = meta['payment_breakdown'] is Map
        ? Map<String, dynamic>.from(meta['payment_breakdown'] as Map)
        : <String, dynamic>{};
    final id = row['id']?.toString() ?? '';
    final fallbackReceipt = id.length <= 8 ? id : id.substring(0, 8);
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) => OrderHistoryLine(
            name: item['snapshot_name']?.toString() ?? 'Produk',
            quantity: _integer(item['qty']),
            price: _number(item['snapshot_price']),
            total: _number(item['total']),
            station: item['station']?.toString(),
          ),
        )
        .toList();

    return OrderHistoryItem(
      id: id,
      receiptNumber:
          payload['receipt_number']?.toString() ??
          (fallbackReceipt.isEmpty ? '-' : fallbackReceipt.toUpperCase()),
      orderType: payload['order_type']?.toString() ?? 'take_away',
      paymentMethod:
          payload['payment_method']?.toString() ??
          payload['paymentMethod']?.toString() ??
          'unknown',
      total: _number(payload['total']),
      subtotal: _number(payload['subtotal']),
      discount: _number(payload['discount_total']),
      tax: _number(payload['tax']),
      amountReceived: meta['amount_received'] == null
          ? null
          : _number(meta['amount_received']),
      change: _number(meta['change']),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      syncStatus: row['status']?.toString() ?? 'pending',
      customerId:
          payload['customer_id']?.toString() ??
          meta['customer_local_id']?.toString(),
      customerName: meta['customer_name']?.toString(),
      tableId: payload['table_id']?.toString(),
      tableName: meta['table_name']?.toString(),
      note: meta['note']?.toString(),
      items: items,
      paymentBreakdown: rawPayments.map(
        (key, value) => MapEntry(key, _number(value)),
      ),
    );
  }

  factory OrderHistoryItem.fromApi(Map<String, dynamic> json) {
    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : <String, dynamic>{};
    final rawItems = json['items'] is List ? json['items'] as List : [];
    final rawPayments = json['payments'] is List
        ? json['payments'] as List
        : [];
    final payments = <String, double>{};
    for (final rawPayment in rawPayments.whereType<Map>()) {
      final payment = Map<String, dynamic>.from(rawPayment);
      final method = payment['method']?.toString() ?? 'unknown';
      payments[method] = (payments[method] ?? 0) + _number(payment['amount']);
    }
    final items = rawItems.whereType<Map>().map((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      return OrderHistoryLine(
        name: item['snapshot_name']?.toString() ?? 'Produk',
        quantity: _integer(item['qty']),
        price: _number(item['snapshot_price']),
        total: _number(item['total']),
        station: item['station']?.toString(),
      );
    }).toList();

    return OrderHistoryItem(
      id: json['id']?.toString() ?? '',
      receiptNumber: json['receipt_number']?.toString() ?? '-',
      orderType: json['order_type']?.toString() ?? 'take_away',
      paymentMethod: payments.keys.firstOrNull ?? 'unknown',
      total: _number(json['total']),
      subtotal: _number(json['subtotal']),
      discount: _number(json['discount_total']),
      tax: _number(json['tax']),
      amountReceived: meta['amount_received'] == null
          ? null
          : _number(meta['amount_received']),
      change: _number(meta['change']),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      syncStatus: 'synced',
      customerId: json['customer_id']?.toString(),
      customerName: meta['customer_name']?.toString(),
      tableId: json['table_id']?.toString(),
      tableName: meta['table_name']?.toString(),
      note: meta['note']?.toString(),
      items: items,
      paymentBreakdown: payments,
    );
  }

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class OrderHistoryLine {
  const OrderHistoryLine({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    this.station,
  });

  final String name;
  final int quantity;
  final double price;
  final double total;
  final String? station;
}
