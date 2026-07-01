import 'package:flutter/material.dart';

class CartItem {
  final String productId;
  final String name;
  final double price;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  double get total => price * quantity;
}

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => _items;

  double get subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get tax => subtotal * 0.11; // 11% PB1 tax
  double get total => subtotal + tax;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  void addItem(String productId, String name, double price) {
    final existingIndex = _items.indexWhere((item) => item.productId == productId);
    if (existingIndex >= 0) {
      _items[existingIndex].quantity += 1;
    } else {
      _items.add(CartItem(productId: productId, name: name, price: price));
    }
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      _items.removeWhere((item) => item.productId == productId);
    } else {
      final item = _items.firstWhere((item) => item.productId == productId);
      item.quantity = quantity;
    }
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
