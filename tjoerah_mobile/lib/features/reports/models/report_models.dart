class SalesReportModel {
  final String date;
  final int orders;
  final double totalSales;
  final double cogs;
  final double grossProfit;

  SalesReportModel({
    required this.date,
    required this.orders,
    required this.totalSales,
    required this.cogs,
    required this.grossProfit,
  });

  factory SalesReportModel.fromJson(Map<String, dynamic> json) {
    return SalesReportModel(
      date: json['date'] as String,
      orders: int.tryParse(json['orders'].toString()) ?? 0,
      totalSales: double.parse(json['total_sales'].toString()),
      cogs: double.parse(json['cogs'].toString()),
      grossProfit: double.parse(json['gross_profit'].toString()),
    );
  }
}

class ProductMarginModel {
  final String productId;
  final String name;
  final int qty;
  final double revenue;
  final double cogs;
  final double marginPercent;

  ProductMarginModel({
    required this.productId,
    required this.name,
    required this.qty,
    required this.revenue,
    required this.cogs,
    required this.marginPercent,
  });

  factory ProductMarginModel.fromJson(Map<String, dynamic> json) {
    final revenue = double.parse(json['revenue'].toString());
    final cogs = double.parse((json['cogs'] ?? 0).toString());
    final profit = revenue - cogs;
    final margin = revenue > 0 ? (profit / revenue) * 100 : 0.0;

    return ProductMarginModel(
      productId: json['product_id'].toString(),
      name: json['snapshot_name'] as String,
      qty: int.tryParse(json['qty'].toString()) ?? 0,
      revenue: revenue,
      cogs: cogs,
      marginPercent: margin,
    );
  }
}

class SystemAlertModel {
  final int id;
  final String title;
  final String message;
  final String severity;
  final DateTime createdAt;

  SystemAlertModel({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.createdAt,
  });

  factory SystemAlertModel.fromJson(Map<String, dynamic> json) {
    return SystemAlertModel(
      id: json['id'] as int,
      title: json['title'] as String,
      message: json['message'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ShiftReportModel {
  final DateTime date;
  final int totalOrders;
  final double grossRevenue;
  final double refundTotal;
  final double totalRevenue;
  final Map<String, double> paymentBreakdown;
  final Map<String, int> paymentCounts;
  final Map<String, double> refundBreakdown;

  ShiftReportModel({
    required this.date,
    required this.totalOrders,
    required this.grossRevenue,
    required this.refundTotal,
    required this.totalRevenue,
    required this.paymentBreakdown,
    required this.paymentCounts,
    this.refundBreakdown = const {},
  });

  factory ShiftReportModel.fromJson(Map<String, dynamic> json) {
    final payments = _doubleMap(json['payment_breakdown']);
    final counts = _intMap(json['payment_counts']);
    for (final method in ['cash', 'qris', 'debit']) {
      payments.putIfAbsent(method, () => 0);
      counts.putIfAbsent(method, () => 0);
    }
    final totalRevenue = _number(json['total_revenue']);
    return ShiftReportModel(
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      totalOrders: _integer(json['total_orders']),
      grossRevenue: json.containsKey('gross_revenue')
          ? _number(json['gross_revenue'])
          : totalRevenue,
      refundTotal: _number(json['refund_total']),
      totalRevenue: totalRevenue,
      paymentBreakdown: payments,
      paymentCounts: counts,
      refundBreakdown: _doubleMap(json['refund_breakdown']),
    );
  }

  factory ShiftReportModel.fromLocalDb(
    DateTime date,
    Map<String, dynamic> dbResult,
  ) {
    return ShiftReportModel.fromJson({...dbResult, 'date': _dateKey(date)});
  }
}

Map<String, double> _doubleMap(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), _number(value)))
    : <String, double>{};

Map<String, int> _intMap(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), _integer(value)))
    : <String, int>{};

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
