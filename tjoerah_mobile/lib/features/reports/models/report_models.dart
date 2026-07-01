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
      orders: json['orders'] as int,
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
      qty: json['qty'] as int,
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
