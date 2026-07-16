class FloorModel {
  final String id;
  final String name;
  final int sortOrder;

  FloorModel({required this.id, required this.name, required this.sortOrder});

  factory FloorModel.fromMap(Map<String, dynamic> map) {
    return FloorModel(
      id: map['id'].toString(),
      name: map['name'].toString(),
      sortOrder: int.tryParse(map['sort_order'].toString()) ?? 0,
    );
  }
}

class DiningTableModel {
  final String id;
  final String? floorId;
  final String name;
  final int capacity;
  final String status; // 'available', 'occupied', 'cleaning'
  final double positionX;
  final double positionY;

  DiningTableModel({
    required this.id,
    this.floorId,
    required this.name,
    required this.capacity,
    required this.status,
    required this.positionX,
    required this.positionY,
  });

  factory DiningTableModel.fromMap(Map<String, dynamic> map) {
    return DiningTableModel(
      id: map['id'].toString(),
      floorId: map['floor_id']?.toString(),
      name: map['name'].toString(),
      capacity: int.tryParse(map['capacity'].toString()) ?? 1,
      status: map['status']?.toString() ?? 'available',
      positionX: double.tryParse(map['position_x'].toString()) ?? 0.0,
      positionY: double.tryParse(map['position_y'].toString()) ?? 0.0,
    );
  }

  DiningTableModel copyWith({
    String? status,
    double? positionX,
    double? positionY,
  }) {
    return DiningTableModel(
      id: id,
      floorId: floorId,
      name: name,
      capacity: capacity,
      status: status ?? this.status,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
    );
  }
}

class TableSessionModel {
  final String id;
  final String tableId;
  final String? orderId;
  final String status; // 'open', 'closed', 'merged'
  final String openedAt;
  final String? mergedToSessionId;

  TableSessionModel({
    required this.id,
    required this.tableId,
    this.orderId,
    required this.status,
    required this.openedAt,
    this.mergedToSessionId,
  });

  factory TableSessionModel.fromMap(Map<String, dynamic> map) {
    return TableSessionModel(
      id: map['id'].toString(),
      tableId: map['table_id'].toString(),
      orderId: map['order_id']?.toString(),
      status: map['status'].toString(),
      openedAt: map['opened_at'].toString(),
      mergedToSessionId: map['merged_to_session_id']?.toString(),
    );
  }
}
