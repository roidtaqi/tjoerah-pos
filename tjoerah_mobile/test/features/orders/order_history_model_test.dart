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
        'customer_id': 42,
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
    expect(order.customerId, '42');
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

  test('parses customer order history returned by the API', () {
    final order = OrderHistoryItem.fromApi({
      'id': 'remote-order',
      'customer_id': 42,
      'receipt_number': 'TJ-REMOTE-001',
      'order_type': 'take_away',
      'subtotal': '35000.00',
      'discount_total': '0.00',
      'tax': '3850.00',
      'total': '38850.00',
      'created_at': '2026-07-29T11:21:00.000000Z',
      'items': [
        {
          'snapshot_name': 'Kopi Tjoerah',
          'snapshot_price': '35000.00',
          'qty': 1,
          'total': '35000.00',
          'station': 'bar',
        },
      ],
      'payments': [
        {'method': 'cash', 'amount': '38850.00'},
      ],
      'meta': {'customer_name': 'Ayu'},
    });

    expect(order.customerId, '42');
    expect(order.customerName, 'Ayu');
    expect(order.receiptNumber, 'TJ-REMOTE-001');
    expect(order.paymentMethod, 'cash');
    expect(order.paymentBreakdown, {'cash': 38850});
    expect(order.items.single.name, 'Kopi Tjoerah');
    expect(order.isPending, isFalse);
  });

  test('summarizes split payment methods for cashier history', () {
    final order = OrderHistoryItem.fromApi({
      'id': 'split-order',
      'receipt_number': 'TJ-SPLIT-001',
      'status': 'paid',
      'total': 50000,
      'created_at': '2026-08-02T10:00:00Z',
      'items': const [],
      'payments': [
        {'method': 'cash', 'amount': 20000},
        {'method': 'qris', 'amount': 30000},
      ],
    });

    expect(order.paymentSummary, 'Tunai + QRIS');
    expect(order.paymentMethods, ['cash', 'qris']);
  });

  test('recognizes a local open bill separately from sync status', () {
    final order = OrderHistoryItem.fromRow({
      'id': 'open-order',
      'created_at': '2026-07-29T12:00:00.000',
      'status': 'synced',
      'payload': jsonEncode({
        'receipt_number': 'TJ-OPEN-001',
        'is_open_bill': true,
        'subtotal': 50000,
        'tax': 5500,
        'total': 55500,
        'items': [
          {
            'product_id': 9,
            'snapshot_name': 'Makan Siang',
            'snapshot_price': 50000,
            'qty': 1,
            'total': 50000,
          },
        ],
        'meta': {
          'server_order_id': 'server-open-order',
          'server_order_status': 'open',
        },
      }),
    });

    expect(order.isOpenBill, isTrue);
    expect(order.isPending, isFalse);
    expect(order.isPaid, isFalse);
    expect(order.serverId, 'server-open-order');
    expect(order.paymentMethod, 'open_bill');
    expect(order.items.single.productId, '9');
    expect(order.toPrintData().isOpenBill, isTrue);
    expect(order.toPrintData().paymentMethodLabel, 'Belum dibayar');
  });

  test(
    'parses cancellation audit and excludes voided order from paid status',
    () {
      final order = OrderHistoryItem.fromApi({
        'id': 'voided-order',
        'receipt_number': 'TJ-VOID-001',
        'status': 'voided',
        'subtotal': '20000.00',
        'total': '20000.00',
        'created_at': '2026-08-02T10:00:00.000000Z',
        'items': const [],
        'payments': [
          {'method': 'cash', 'amount': '20000.00'},
        ],
        'refunds': [
          {'status': 'approved', 'amount': '20000.00'},
        ],
        'meta': {
          'cancellation': {
            'reason': 'Transaksi salah input.',
            'inventory_outcome': 'restore_stock',
            'cancelled_at': '2026-08-02T10:05:00+08:00',
          },
        },
      });

      expect(order.isVoided, isTrue);
      expect(order.isPaid, isFalse);
      expect(order.canBeCancelled, isFalse);
      expect(order.refundedAmount, 20000);
      expect(order.cancellationReason, 'Transaksi salah input.');
      expect(order.cancellationInventoryOutcome, 'restore_stock');
      expect(order.cancelledAt, isNotNull);
      expect(order.toPrintData().isCancelled, isTrue);
      expect(order.toPrintData().cancellationReason, 'Transaksi salah input.');
    },
  );
}
