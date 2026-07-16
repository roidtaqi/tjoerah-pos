import 'dart:convert';

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
    this.customerName,
    this.tableId,
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
  final String? customerName;
  final String? tableId;
  final String? note;

  bool get isPending => syncStatus == 'pending';
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

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
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      syncStatus: row['status']?.toString() ?? 'pending',
      customerName: meta['customer_name']?.toString(),
      tableId: payload['table_id']?.toString(),
      note: meta['note']?.toString(),
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => OrderHistoryLine(
              name: item['snapshot_name']?.toString() ?? 'Produk',
              quantity: _integer(item['qty']),
              price: _number(item['snapshot_price']),
              total: _number(item['total']),
            ),
          )
          .toList(),
      paymentBreakdown: rawPayments.map(
        (key, value) => MapEntry(key, _number(value)),
      ),
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
  });

  final String name;
  final int quantity;
  final double price;
  final double total;
}
