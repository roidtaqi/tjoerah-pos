import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/printer/print_job.dart';

void main() {
  test('groups production items by station with kitchen as fallback', () {
    final order = _order([
      const PrintOrderItem(
        name: 'Es Kopi Susu',
        quantity: 2,
        unitPrice: 22000,
        station: 'bar',
      ),
      const PrintOrderItem(
        name: 'Nasi Goreng',
        quantity: 1,
        unitPrice: 35000,
        station: 'kitchen',
      ),
      const PrintOrderItem(
        name: 'Kentang Goreng',
        quantity: 1,
        unitPrice: 18000,
      ),
    ]);

    expect(order.itemsByStation.keys, containsAll(['bar', 'kitchen']));
    expect(order.itemsByStation['bar'], hasLength(1));
    expect(order.itemsByStation['kitchen'], hasLength(2));
    expect(productionStationLabel('kitchen'), 'Dapur');
    expect(productionStationLabel('bar'), 'Bar');
  });

  test('provides stable receipt labels and totals', () {
    final order = _order([
      const PrintOrderItem(name: 'Americano', quantity: 2, unitPrice: 20000),
    ]);

    expect(order.shortOrderId, '12345678');
    expect(order.paymentMethodLabel, 'Tunai');
    expect(order.items.single.total, 40000);
  });
}

TransactionPrintData _order(List<PrintOrderItem> items) {
  return TransactionPrintData(
    orderId: '12345678-abcd-efgh',
    receiptNumber: 'TJ-260717-001',
    createdAt: DateTime(2026, 7, 17, 12),
    orderTypeLabel: 'Makan di tempat',
    tableName: 'Meja 4',
    paymentMethod: 'cash',
    paymentBreakdown: const {'cash': 40000},
    items: items,
    subtotal: 40000,
    discount: 0,
    tax: 4400,
    total: 44400,
    amountReceived: 50000,
    change: 5600,
    isSynced: true,
  );
}
