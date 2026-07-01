import 'package:uuid/uuid.dart';

import '../../../core/database/local_db.dart';
import '../../../core/sync/sync_manager.dart';
import '../providers/cart_provider.dart';

class OrderRepository {
  static const _uuid = Uuid();

  /// Creates an order from the given cart items, stores it locally (unsynced),
  /// and queues it in the sync pipeline.
  ///
  /// Returns the generated order UUID.
  Future<String> createOrder({
    required List<CartItem> items,
    required double subtotal,
    required double tax,
    required double total,
  }) async {
    final db = await LocalDatabase.instance.database;
    final orderId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    // Insert the order header
    await db.insert('orders', {
      'id': orderId,
      'total': total,
      'status': 'paid',
      'created_at': now,
      'is_synced': 0,
    });

    // Insert each order item
    final itemPayloads = <Map<String, dynamic>>[];
    for (final item in items) {
      final itemId = _uuid.v4();

      await db.insert('order_items', {
        'id': itemId,
        'order_id': orderId,
        'product_id': item.productId,
        'quantity': item.quantity,
        'price': item.price,
      });

      itemPayloads.add({
        'id': itemId,
        'product_id': item.productId,
        'quantity': item.quantity,
        'price': item.price,
      });
    }

    // Queue the full order for background sync
    await SyncManager.instance.queueOperation('CREATE', 'ORDER', {
      'id': orderId,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'status': 'paid',
      'created_at': now,
      'items': itemPayloads,
    });

    return orderId;
  }
}
