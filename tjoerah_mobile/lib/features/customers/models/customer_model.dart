class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.name,
    required this.totalSpent,
    required this.visitCount,
    required this.isSynced,
    this.phone,
    this.email,
    this.birthday,
    this.notes,
    this.lastPurchaseAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final DateTime? birthday;
  final String? notes;
  final double totalSpent;
  final int visitCount;
  final DateTime? lastPurchaseAt;
  final bool isSynced;

  factory CustomerModel.fromJson(
    Map<String, dynamic> json, {
    bool isSynced = true,
  }) {
    return CustomerModel(
      id: json['id']?.toString() ?? json['uuid']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Pelanggan',
      phone: _nullable(json['phone']),
      email: _nullable(json['email']),
      birthday: DateTime.tryParse(json['birthday']?.toString() ?? ''),
      notes: _nullable(json['notes']),
      totalSpent: _number(json['total_spent']),
      visitCount: _integer(json['visit_count']),
      lastPurchaseAt: DateTime.tryParse(
        json['last_purchase_at']?.toString() ?? '',
      ),
      isSynced: isSynced,
    );
  }

  factory CustomerModel.fromRow(Map<String, Object?> row) {
    return CustomerModel.fromJson(
      Map<String, dynamic>.from(row),
      isSynced: row['is_synced'] == 1,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'birthday': birthday?.toIso8601String(),
    'notes': notes,
    'total_spent': totalSpent,
    'visit_count': visitCount,
    'last_purchase_at': lastPurchaseAt?.toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
    'updated_at': DateTime.now().toIso8601String(),
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

class CustomerDraft {
  const CustomerDraft({required this.name, this.phone, this.email, this.notes});

  final String name;
  final String? phone;
  final String? email;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (phone != null && phone!.isNotEmpty) 'phone': phone,
    if (email != null && email!.isNotEmpty) 'email': email,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };
}
