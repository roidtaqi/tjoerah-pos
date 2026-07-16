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
}
