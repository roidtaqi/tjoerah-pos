import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.station,
    this.quantity = 1,
    this.isManual = false,
  });

  final String productId;
  final String name;
  final double price;
  final String? station;
  final int quantity;
  final bool isManual;

  double get total => price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      productId: productId,
      name: name,
      price: price,
      station: station,
      quantity: quantity ?? this.quantity,
      isManual: isManual,
    );
  }
}

class SubmittedCartItem {
  const SubmittedCartItem({
    required this.name,
    required this.price,
    required this.quantity,
    required this.submittedAt,
    this.productId,
    this.station,
    this.submissionBatch = 1,
  });

  final String? productId;
  final String name;
  final double price;
  final int quantity;
  final String? station;
  final int submissionBatch;
  final DateTime submittedAt;

  double get total => price * quantity;
}

class OpenBillCartContext {
  const OpenBillCartContext({
    required this.serverId,
    required this.receiptNumber,
    required this.createdAt,
    required this.label,
  });

  final String serverId;
  final String receiptNumber;
  final DateTime createdAt;
  final String label;
}

class CartState {
  const CartState({
    this.items = const [],
    this.orderType = 'take_away',
    this.tableId,
    this.tableName,
    this.discountPercent = 0,
    this.note = '',
    this.customerId,
    this.customerName,
    this.taxEnabled = true,
    this.taxRate = 11,
    this.submittedItems = const [],
    this.openBill,
  });

  final List<CartItem> items;
  final String orderType;
  final String? tableId;
  final String? tableName;
  final double discountPercent;
  final String note;
  final String? customerId;
  final String? customerName;
  final bool taxEnabled;
  final double taxRate;
  final List<SubmittedCartItem> submittedItems;
  final OpenBillCartContext? openBill;

  bool get isEditingOpenBill => openBill != null;
  double get newItemsSubtotal => items.fold(0, (sum, item) => sum + item.total);
  double get submittedSubtotal =>
      submittedItems.fold(0, (sum, item) => sum + item.total);
  double get subtotal => submittedSubtotal + newItemsSubtotal;
  double get discount => subtotal * (discountPercent / 100);
  double get taxableAmount => subtotal - discount;
  double get tax => taxEnabled
      ? (taxableAmount * (taxRate / 100) * 100).roundToDouble() / 100
      : 0;
  double get total => taxableAmount + tax;
  int get itemCount =>
      items.fold(0, (sum, item) => sum + item.quantity) +
      submittedItems.fold(0, (sum, item) => sum + item.quantity);

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
    String? customerId,
    String? customerName,
    bool clearCustomer = false,
    bool clearCustomerId = false,
    bool? taxEnabled,
    double? taxRate,
    List<SubmittedCartItem>? submittedItems,
    OpenBillCartContext? openBill,
    bool clearOpenBill = false,
  }) {
    return CartState(
      items: items ?? this.items,
      orderType: orderType ?? this.orderType,
      tableId: clearTable ? null : (tableId ?? this.tableId),
      tableName: clearTable ? null : (tableName ?? this.tableName),
      discountPercent: discountPercent ?? this.discountPercent,
      note: note ?? this.note,
      customerId: clearCustomer || clearCustomerId
          ? null
          : (customerId ?? this.customerId),
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxRate: taxRate ?? this.taxRate,
      submittedItems: clearOpenBill
          ? const []
          : (submittedItems ?? this.submittedItems),
      openBill: clearOpenBill ? null : (openBill ?? this.openBill),
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

  void setTaxSettings({required bool enabled, required double rate}) {
    state = state.copyWith(taxEnabled: enabled, taxRate: rate.clamp(0, 100));
  }

  void setCustomer(String? name, {String? id}) {
    state = name == null || name.trim().isEmpty
        ? state.copyWith(clearCustomer: true)
        : state.copyWith(
            customerId: id,
            customerName: name.trim(),
            clearCustomerId: id == null,
          );
  }

  void startOpenBillEdit({
    required String serverId,
    required String receiptNumber,
    required DateTime createdAt,
    required String openBillLabel,
    required List<SubmittedCartItem> submittedItems,
    required String orderType,
    required double discountPercent,
    required bool taxEnabled,
    required double taxRate,
    String? tableId,
    String? tableName,
    String? customerId,
    String? customerName,
    String note = '',
  }) {
    state = CartState(
      orderType: orderType,
      tableId: tableId,
      tableName: tableName,
      discountPercent: discountPercent,
      note: note,
      customerId: customerId,
      customerName: customerName,
      taxEnabled: taxEnabled,
      taxRate: taxRate,
      submittedItems: submittedItems,
      openBill: OpenBillCartContext(
        serverId: serverId,
        receiptNumber: receiptNumber,
        createdAt: createdAt,
        label: openBillLabel,
      ),
    );
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

  void addManualItem(String description, double price, {int quantity = 1}) {
    final itemId = 'manual-${DateTime.now().microsecondsSinceEpoch}';
    state = state.copyWith(
      items: [
        ...state.items,
        CartItem(
          productId: itemId,
          name: description.trim(),
          price: price,
          station: 'cashier',
          quantity: quantity,
          isManual: true,
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

  void markOpenBillItemsSubmitted({
    required int submissionBatch,
    DateTime? submittedAt,
  }) {
    if (!state.isEditingOpenBill || state.items.isEmpty) return;
    final timestamp = submittedAt ?? DateTime.now();
    final submitted = state.items
        .map(
          (item) => SubmittedCartItem(
            productId: item.isManual ? null : item.productId,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            station: item.station,
            submissionBatch: submissionBatch,
            submittedAt: timestamp,
          ),
        )
        .toList();
    state = state.copyWith(
      items: const [],
      submittedItems: [...state.submittedItems, ...submitted],
    );
  }

  void clearCart() {
    state = CartState(
      orderType: state.orderType,
      taxEnabled: state.taxEnabled,
      taxRate: state.taxRate,
    );
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);
