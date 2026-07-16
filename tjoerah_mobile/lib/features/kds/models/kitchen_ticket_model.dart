class KitchenTicketItemModel {
  final String id;
  final String orderItemId;
  final String name;
  final int qty;
  final Map<String, dynamic>? modifiers;
  final String? notes;
  final String status;

  KitchenTicketItemModel({
    required this.id,
    required this.orderItemId,
    required this.name,
    required this.qty,
    this.modifiers,
    this.notes,
    required this.status,
  });

  factory KitchenTicketItemModel.fromJson(Map<String, dynamic> json) {
    return KitchenTicketItemModel(
      id: json['id'] as String,
      orderItemId: json['order_item_id'] as String,
      name: json['name'] as String,
      qty: json['qty'] as int,
      modifiers: json['modifiers'] as Map<String, dynamic>?,
      notes: json['notes'] as String?,
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_item_id': orderItemId,
      'name': name,
      'qty': qty,
      'modifiers': modifiers,
      'notes': notes,
      'status': status,
    };
  }
}

class KitchenTicketModel {
  final String id;
  final String orderId;
  final int? outletId;
  final String station;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final List<KitchenTicketItemModel> items;

  KitchenTicketModel({
    required this.id,
    required this.orderId,
    this.outletId,
    required this.station,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.acceptedAt,
    this.preparingAt,
    this.readyAt,
    this.completedAt,
    required this.items,
  });

  factory KitchenTicketModel.fromJson(Map<String, dynamic> json) {
    return KitchenTicketModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      outletId: json['outlet_id'] as int?,
      station: json['station'] as String,
      status: json['status'] as String,
      priority: json['priority'] as String? ?? 'normal',
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      preparingAt: json['preparing_at'] != null
          ? DateTime.parse(json['preparing_at'] as String)
          : null,
      readyAt: json['ready_at'] != null
          ? DateTime.parse(json['ready_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      items:
          (json['items'] as List<dynamic>?)
              ?.map(
                (item) => KitchenTicketItemModel.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'outlet_id': outletId,
      'station': station,
      'status': status,
      'priority': priority,
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'preparing_at': preparingAt?.toIso8601String(),
      'ready_at': readyAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  KitchenTicketModel copyWith({
    String? status,
    DateTime? acceptedAt,
    DateTime? preparingAt,
    DateTime? readyAt,
    DateTime? completedAt,
  }) {
    return KitchenTicketModel(
      id: id,
      orderId: orderId,
      outletId: outletId,
      station: station,
      status: status ?? this.status,
      priority: priority,
      createdAt: createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      preparingAt: preparingAt ?? this.preparingAt,
      readyAt: readyAt ?? this.readyAt,
      completedAt: completedAt ?? this.completedAt,
      items: items,
    );
  }
}
