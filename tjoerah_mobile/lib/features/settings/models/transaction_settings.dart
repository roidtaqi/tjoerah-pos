class TransactionSettings {
  const TransactionSettings({
    required this.outletId,
    required this.taxEnabled,
    required this.taxRate,
    required this.kdsMode,
  });

  final int outletId;
  final bool taxEnabled;
  final double taxRate;
  final String kdsMode;

  bool get manualKds => kdsMode == 'manual';

  double get effectiveTaxRate => taxEnabled ? taxRate : 0;

  factory TransactionSettings.fromJson(Map<String, dynamic> json) {
    return TransactionSettings(
      outletId: _integer(json['outlet_id']),
      taxEnabled: _boolean(json['tax_enabled'], fallback: true),
      taxRate: _number(json['tax_rate'], fallback: 11).clamp(0, 100),
      kdsMode: json['kds_mode']?.toString() ?? 'manual',
    );
  }

  Map<String, dynamic> toJson() => {
    'outlet_id': outletId,
    'tax_enabled': taxEnabled,
    'tax_rate': taxRate,
    'kds_mode': kdsMode,
  };
}

double _number(Object? value, {required double fallback}) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

bool _boolean(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains(value.toString().toLowerCase());
}
