class PrintOrderItem {
  const PrintOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.station,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final String? station;

  double get total => unitPrice * quantity;
}

class TransactionPrintData {
  TransactionPrintData({
    required this.orderId,
    required this.receiptNumber,
    required this.createdAt,
    required this.orderTypeLabel,
    required this.paymentMethod,
    required Map<String, double> paymentBreakdown,
    required List<PrintOrderItem> items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.isSynced,
    this.tableName,
    this.customerName,
    this.note,
    this.amountReceived,
    this.change = 0,
  }) : paymentBreakdown = Map.unmodifiable(paymentBreakdown),
       items = List.unmodifiable(items);

  final String orderId;
  final String receiptNumber;
  final DateTime createdAt;
  final String orderTypeLabel;
  final String paymentMethod;
  final Map<String, double> paymentBreakdown;
  final List<PrintOrderItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final bool isSynced;
  final String? tableName;
  final String? customerName;
  final String? note;
  final double? amountReceived;
  final double change;

  String get shortOrderId => orderId.length <= 8
      ? orderId.toUpperCase()
      : orderId.substring(0, 8).toUpperCase();

  String get paymentMethodLabel => switch (paymentMethod) {
    'cash' => 'Tunai',
    'qris' => 'QRIS',
    'card' => 'Kartu',
    'split' => 'Pembayaran terpisah',
    _ => paymentMethod,
  };

  Map<String, List<PrintOrderItem>> get itemsByStation {
    final groups = <String, List<PrintOrderItem>>{};
    for (final item in items) {
      final station = item.station?.trim().toLowerCase();
      final key = station == null || station.isEmpty ? 'kitchen' : station;
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups;
  }
}

String productionStationLabel(String station) => switch (station) {
  'bar' => 'Bar',
  'kitchen' => 'Dapur',
  _ =>
    station.isEmpty
        ? 'Dapur'
        : '${station[0].toUpperCase()}${station.substring(1)}',
};
