import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.station,
    this.quantity = 1,
  });

  final String productId;
  final String name;
  final double price;
  final String? station;
  final int quantity;

  double get total => price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      productId: productId,
      name: name,
      price: price,
      station: station,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartState {
  const CartState({
    this.items = const [],
    this.orderType = 'take_away',
    this.tableId,
    this.tableName,
    this.discountPercent = 0,
    this.note = '',
    this.customerName,
  });

  final List<CartItem> items;
  final String orderType;
  final String? tableId;
  final String? tableName;
  final double discountPercent;
  final String note;
  final String? customerName;

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);
  double get discount => subtotal * (discountPercent / 100);
  double get taxableAmount => subtotal - discount;
  double get tax => taxableAmount * 0.11;
  double get total => taxableAmount + tax;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  String get orderTypeLabel => switch (orderType) {
    'dine_in' => 'Makan di tempat',
    'delivery' => 'Pesan antar',
    _ => 'Bawa pulang',
  };

  CartState copyWith({
    List<CartItem>? items,
    String? orderType,
    String? tableId,
    String? tableName,
    bool clearTable = false,
    double? discountPercent,
    String? note,
    String? customerName,
    bool clearCustomer = false,
  }) {
    return CartState(
      items: items ?? this.items,
      orderType: orderType ?? this.orderType,
      tableId: clearTable ? null : (tableId ?? this.tableId),
      tableName: clearTable ? null : (tableName ?? this.tableName),
      discountPercent: discountPercent ?? this.discountPercent,
      note: note ?? this.note,
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void setOrderType(String type) {
    state = state.copyWith(orderType: type, clearTable: type != 'dine_in');
  }

  void setTable(String? id, {String? name}) {
    state = id == null
        ? state.copyWith(clearTable: true)
        : state.copyWith(tableId: id, tableName: name);
  }

  void setTableId(String? id) => setTable(id);

  void setDiscount(double percent) {
    state = state.copyWith(discountPercent: percent.clamp(0, 100));
  }

  void setNote(String note) => state = state.copyWith(note: note.trim());

  void setCustomer(String? name) {
    state = name == null || name.trim().isEmpty
        ? state.copyWith(clearCustomer: true)
        : state.copyWith(customerName: name.trim());
  }

  void addItem(String productId, String name, double price, {String? station}) {
    final existingIndex = state.items.indexWhere(
      (item) => item.productId == productId,
    );

    if (existingIndex >= 0) {
      final updatedItems = [...state.items];
      final item = updatedItems[existingIndex];
      updatedItems[existingIndex] = item.copyWith(quantity: item.quantity + 1);
      state = state.copyWith(items: updatedItems);
      return;
    }

    state = state.copyWith(
      items: [
        ...state.items,
        CartItem(
          productId: productId,
          name: name,
          price: price,
          station: station,
        ),
      ],
    );
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      state = state.copyWith(
        items: state.items
            .where((item) => item.productId != productId)
            .toList(),
      );
      return;
    }

    state = state.copyWith(
      items: state.items
          .map(
            (item) => item.productId == productId
                ? item.copyWith(quantity: quantity)
                : item,
          )
          .toList(),
    );
  }

  void clearCart() {
    state = CartState(orderType: state.orderType);
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);
