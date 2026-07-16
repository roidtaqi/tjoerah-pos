class OutletSummaryModel {
  const OutletSummaryModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.orders,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    this.address,
    this.phone,
  });

  final String id;
  final String name;
  final String? address;
  final String? phone;
  final bool isActive;
  final int orders;
  final double revenue;
  final double cogs;
  final double grossProfit;

  double get marginPercent => revenue == 0 ? 0 : grossProfit / revenue * 100;
  bool get needsAttention => !isActive || marginPercent < 55;

  factory OutletSummaryModel.fromJson(Map<String, dynamic> json) {
    return OutletSummaryModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Outlet',
      address: _nullable(json['address']),
      phone: _nullable(json['phone']),
      isActive: json['is_active'] == true || json['is_active'] == 1,
      orders: _integer(json['orders']),
      revenue: _number(json['revenue']),
      cogs: _number(json['cogs']),
      grossProfit: _number(json['gross_profit']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'phone': phone,
    'is_active': isActive,
    'orders': orders,
    'revenue': revenue,
    'cogs': cogs,
    'gross_profit': grossProfit,
  };

  static String? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
