import 'dart:convert';

import '../../../core/printer/print_job.dart';

class OrderHistoryItem {
  const OrderHistoryItem({
    required this.id,
    this.serverId,
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
    this.orderStatus = 'completed',
    this.refundedAmount = 0,
    this.cancellationReason,
    this.cancellationInventoryOutcome,
    this.cancelledAt,
    this.openBillLabel,
  });

  final String id;
  final String? serverId;
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
  final String orderStatus;
  final double refundedAmount;
  final String? cancellationReason;
  final String? cancellationInventoryOutcome;
  final DateTime? cancelledAt;
  final String? openBillLabel;

  String get openBillDisplayLabel => openBillLabel?.trim().isNotEmpty == true
      ? openBillLabel!.trim()
      : customerName?.trim().isNotEmpty == true
      ? customerName!.trim()
      : tableName?.trim().isNotEmpty == true
      ? tableName!.trim()
      : receiptNumber;

  String get openBillHeading {
    final parts = <String>[];
    for (final value in [customerName, openBillLabel, tableName]) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty ||
          parts.any((part) => part.toLowerCase() == normalized.toLowerCase())) {
        continue;
      }
      parts.add(normalized);
    }
    return parts.isEmpty ? openBillDisplayLabel : parts.join(' • ');
  }

  bool get isPending => syncStatus == 'pending';
  bool get isOpenBill => orderStatus == 'open' || orderStatus == 'held';
  bool get isPaid => const {
    'paid',
    'completed',
    'partially_refunded',
    'refunded',
  }.contains(orderStatus);
  bool get isRefunded =>
      orderStatus == 'refunded' || orderStatus == 'partially_refunded';
  bool get isVoided => orderStatus == 'voided';
  bool get canBeCancelled => const {
    'draft',
    'open',
    'held',
    'paid',
    'completed',
    'partially_refunded',
    'refunded',
  }.contains(orderStatus);
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  double get taxRate {
    final taxable = subtotal - discount;
    return taxable > 0 ? (tax / taxable) * 100 : 0;
  }

  List<String> get paymentMethods => paymentBreakdown.keys.isNotEmpty
      ? paymentBreakdown.keys.toList()
      : [paymentMethod];

  String get paymentSummary => isOpenBill
      ? 'Belum dibayar'
      : paymentMethods.map(_paymentMethodLabel).join(' + ');

  TransactionPrintData toPrintData({
    String? paymentMethod,
    Map<String, double>? paymentBreakdown,
    double? amountReceived,
    double? change,
    bool isReprint = true,
  }) {
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
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentBreakdown: paymentBreakdown ?? this.paymentBreakdown,
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
      isReprint: isReprint,
      tableName: tableName ?? (tableId == null ? null : 'Meja $tableId'),
      customerName: customerName,
      note: note ?? (isOpenBill ? 'Open bill: $openBillDisplayLabel' : null),
      amountReceived: amountReceived ?? this.amountReceived,
      change: change ?? this.change,
      isCancelled: isVoided,
      cancellationReason: cancellationReason,
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
    final cancellation = meta['cancellation'] is Map
        ? Map<String, dynamic>.from(meta['cancellation'] as Map)
        : <String, dynamic>{};
    final id = row['id']?.toString() ?? '';
    final fallbackReceipt = id.length <= 8 ? id : id.substring(0, 8);
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) => OrderHistoryLine(
            id: item['server_order_item_id']?.toString(),
            productId: item['product_id']?.toString(),
            name: item['snapshot_name']?.toString() ?? 'Produk',
            quantity: _integer(item['qty']),
            price: _number(item['snapshot_price']),
            total: _number(item['total']),
            station: item['station']?.toString(),
            submissionBatch: _batch(item['submission_batch']),
            submittedAt: DateTime.tryParse(
              item['submitted_at']?.toString() ?? '',
            ),
          ),
        )
        .toList();

    return OrderHistoryItem(
      id: id,
      serverId: meta['server_order_id']?.toString(),
      receiptNumber:
          payload['receipt_number']?.toString() ??
          (fallbackReceipt.isEmpty ? '-' : fallbackReceipt.toUpperCase()),
      orderType: payload['order_type']?.toString() ?? 'take_away',
      paymentMethod:
          payload['payment_method']?.toString() ??
          payload['paymentMethod']?.toString() ??
          (payload['is_open_bill'] == true ? 'open_bill' : 'unknown'),
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
      orderStatus:
          meta['server_order_status']?.toString() ??
          (payload['is_open_bill'] == true ? 'open' : 'completed'),
      refundedAmount: _number(meta['refunded_amount']),
      cancellationReason: cancellation['reason']?.toString(),
      cancellationInventoryOutcome: cancellation['inventory_outcome']
          ?.toString(),
      cancelledAt: DateTime.tryParse(
        cancellation['cancelled_at']?.toString() ?? '',
      ),
      openBillLabel: meta['open_bill_label']?.toString(),
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
    final cancellation = meta['cancellation'] is Map
        ? Map<String, dynamic>.from(meta['cancellation'] as Map)
        : <String, dynamic>{};
    final rawPayments = json['payments'] is List
        ? json['payments'] as List
        : [];
    final payments = <String, double>{};
    for (final rawPayment in rawPayments.whereType<Map>()) {
      final payment = Map<String, dynamic>.from(rawPayment);
      final method = payment['method']?.toString() ?? 'unknown';
      payments[method] = (payments[method] ?? 0) + _number(payment['amount']);
    }
    final metaPayments = meta['payment_breakdown'] is Map
        ? Map<String, dynamic>.from(
            meta['payment_breakdown'] as Map,
          ).map((method, amount) => MapEntry(method, _number(amount)))
        : <String, double>{};
    final paymentBreakdown = metaPayments.isNotEmpty ? metaPayments : payments;
    final items = rawItems.whereType<Map>().map((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      return OrderHistoryLine(
        id: item['id']?.toString(),
        productId: item['product_id']?.toString(),
        name: item['snapshot_name']?.toString() ?? 'Produk',
        quantity: _integer(item['qty']),
        price: _number(item['snapshot_price']),
        total: _number(item['total']),
        station: item['station']?.toString(),
        submissionBatch: _batch(item['submission_batch']),
        submittedAt: DateTime.tryParse(item['submitted_at']?.toString() ?? ''),
      );
    }).toList();
    final rawRefunds = json['refunds'] is List ? json['refunds'] as List : [];
    final refundedAmount = rawRefunds
        .whereType<Map>()
        .where((refund) => refund['status']?.toString() == 'approved')
        .fold<double>(0, (sum, refund) => sum + _number(refund['amount']));

    return OrderHistoryItem(
      id: json['id']?.toString() ?? '',
      serverId: json['id']?.toString(),
      receiptNumber: json['receipt_number']?.toString() ?? '-',
      orderType: json['order_type']?.toString() ?? 'take_away',
      paymentMethod:
          (paymentBreakdown.length > 1
              ? 'split'
              : paymentBreakdown.keys.firstOrNull) ??
          (json['status']?.toString() == 'open' ? 'open_bill' : 'unknown'),
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
      orderStatus: json['status']?.toString() ?? 'completed',
      refundedAmount: refundedAmount,
      cancellationReason: cancellation['reason']?.toString(),
      cancellationInventoryOutcome: cancellation['inventory_outcome']
          ?.toString(),
      cancelledAt: DateTime.tryParse(
        cancellation['cancelled_at']?.toString() ?? '',
      ),
      openBillLabel: meta['open_bill_label']?.toString(),
      items: items,
      paymentBreakdown: paymentBreakdown,
    );
  }

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static int _batch(Object? value) {
    final parsed = _integer(value);
    return parsed < 1 ? 1 : parsed;
  }
}

class OrderHistoryLine {
  const OrderHistoryLine({
    this.id,
    this.productId,
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    this.station,
    this.submissionBatch = 1,
    this.submittedAt,
  });

  final String? id;
  final String? productId;
  final String name;
  final int quantity;
  final double price;
  final double total;
  final String? station;
  final int submissionBatch;
  final DateTime? submittedAt;
}

String _paymentMethodLabel(String method) => switch (method.toLowerCase()) {
  'cash' => 'Tunai',
  'qris' => 'QRIS',
  'debit' || 'debit_card' || 'card' => 'Kartu debit',
  'open_bill' => 'Belum dibayar',
  _ => method.replaceAll('_', ' '),
};
