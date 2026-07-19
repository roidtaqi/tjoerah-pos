import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/orders/models/order_history_model.dart';

void main() {
  test('rebuilds receipt and production print data from local history', () {
    final order = OrderHistoryItem.fromRow({
      'id': '12345678-abcd-efgh',
      'created_at': '2026-07-19T10:30:00.000',
      'status': 'synced',
      'payload': jsonEncode({
        'receipt_number': 'TJ-260719-001',
        'order_type': 'dine_in',
        'table_id': 4,
        'subtotal': 60000,
        'discount_total': 5000,
        'tax': 6050,
        'total': 61050,
        'payment_method': 'cash',
        'items': [
          {
            'snapshot_name': 'Nasi Goreng',
            'snapshot_price': 35000,
            'qty': 1,
            'total': 35000,
            'station': 'kitchen',
          },
          {
            'snapshot_name': 'Es Kopi',
            'snapshot_price': 25000,
            'qty': 1,
            'total': 25000,
            'station': 'bar',
          },
        ],
        'meta': {
          'table_name': 'Meja A4',
          'customer_name': 'Roid',
          'note': 'Tanpa pedas',
          'amount_received': 70000,
          'change': 8950,
          'payment_breakdown': {'cash': 61050},
        },
      }),
    });

    final printData = order.toPrintData();

    expect(printData.isReprint, isTrue);
    expect(printData.tableName, 'Meja A4');
    expect(printData.amountReceived, 70000);
    expect(printData.change, 8950);
    expect(printData.itemsByStation.keys, containsAll(['kitchen', 'bar']));
    expect(printData.subtotal, 60000);
    expect(printData.tax, 6050);
  });

  test('old orders without station fall back to the kitchen printer', () {
    final order = OrderHistoryItem.fromRow({
      'id': 'old-order',
      'created_at': '2026-07-19T10:30:00.000',
      'status': 'pending',
      'payload': jsonEncode({
        'total': 20000,
        'items': [
          {
            'snapshot_name': 'Produk lama',
            'snapshot_price': 20000,
            'qty': 1,
            'total': 20000,
          },
        ],
      }),
    });

    final printData = order.toPrintData();

    expect(printData.itemsByStation.keys, ['kitchen']);
    expect(printData.isSynced, isFalse);
    expect(printData.subtotal, 20000);
  });
}
