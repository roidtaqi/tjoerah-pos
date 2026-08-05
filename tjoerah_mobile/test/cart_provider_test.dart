import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tjoerah_mobile/features/pos/providers/cart_provider.dart';

void main() {
  test('cart calculates totals and clears table when order type changes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);

    cart.setOrderType('dine_in');
    cart.setTable('12', name: 'Meja 12');
    cart.addItem('1', 'Kopi Susu', 20000, station: 'bar');
    cart.addItem('1', 'Kopi Susu', 20000, station: 'bar');
    cart.setDiscount(10);

    final state = container.read(cartProvider);
    expect(state.itemCount, 2);
    expect(state.subtotal, 40000);
    expect(state.discount, 4000);
    expect(state.tax, 3960);
    expect(state.total, 39960);
    expect(state.tableName, 'Meja 12');
    expect(state.items.single.station, 'bar');

    cart.setOrderType('delivery');
    final delivery = container.read(cartProvider);
    expect(delivery.tableId, isNull);
    expect(delivery.tableName, isNull);
    expect(delivery.orderTypeLabel, 'Pesan antar');
  });

  test('cart keeps the selected customer identity until it is cleared', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);

    cart.setCustomer('Ayu', id: '42');
    expect(container.read(cartProvider).customerId, '42');
    expect(container.read(cartProvider).customerName, 'Ayu');

    cart.setCustomer(null);
    expect(container.read(cartProvider).customerId, isNull);
    expect(container.read(cartProvider).customerName, isNull);
  });

  test('manual items stay separate and do not use a production station', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);

    cart.addManualItem('Biaya dekorasi', 15000, quantity: 2);
    cart.addManualItem('Biaya dekorasi', 15000);

    final items = container.read(cartProvider).items;
    expect(items, hasLength(2));
    expect(items.first.isManual, isTrue);
    expect(items.first.station, 'cashier');
    expect(items.first.total, 30000);
    expect(items.first.productId, startsWith('manual-'));
  });

  test('cart applies configurable tax after the order discount', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);

    cart.addItem('1', 'Kopi Susu', 100000);
    cart.setDiscount(10);
    cart.setTaxSettings(enabled: true, rate: 8.5);

    expect(container.read(cartProvider).taxableAmount, 90000);
    expect(container.read(cartProvider).tax, 7650);
    expect(container.read(cartProvider).total, 97650);

    cart.setTaxSettings(enabled: false, rate: 8.5);
    expect(container.read(cartProvider).tax, 0);
    expect(container.read(cartProvider).total, 90000);

    cart.clearCart();
    expect(container.read(cartProvider).taxEnabled, isFalse);
    expect(container.read(cartProvider).taxRate, 8.5);
  });

  test('restored open bill separates submitted and new items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);

    cart.startOpenBillEdit(
      serverId: 'server-order',
      receiptNumber: 'TJ-OPEN-001',
      createdAt: DateTime(2026, 8, 2, 10),
      openBillLabel: 'Meja 4',
      submittedItems: [
        SubmittedCartItem(
          productId: '1',
          name: 'Nasi Goreng',
          price: 35000,
          quantity: 1,
          station: 'kitchen',
          submissionBatch: 1,
          submittedAt: DateTime(2026, 8, 2, 10),
        ),
      ],
      orderType: 'dine_in',
      discountPercent: 10,
      taxEnabled: true,
      taxRate: 11,
      tableId: '4',
      tableName: 'Meja 4',
    );
    cart.addItem('2', 'Es Kopi', 25000, station: 'bar');

    final state = container.read(cartProvider);
    expect(state.isEditingOpenBill, isTrue);
    cart.markOpenBillItemsSubmitted(submissionBatch: 2);
    final submitted = container.read(cartProvider);
    expect(submitted.items, isEmpty);
    expect(submitted.submittedItems, hasLength(2));
    expect(submitted.isEditingOpenBill, isTrue);
    expect(state.submittedItems, hasLength(1));
    expect(state.items, hasLength(1));
    expect(state.subtotal, 60000);
    expect(state.discount, 6000);
    expect(state.tax, 5940);
    expect(state.total, 59940);
  });
}
