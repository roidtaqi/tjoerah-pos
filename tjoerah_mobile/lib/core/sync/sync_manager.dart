import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/local_db.dart';
import '../network/api_client.dart';

class SyncManager {
  static final SyncManager instance = SyncManager._init();
  final _uuid = const Uuid();

  SyncManager._init();

  /// Records an operation into the local sync queue (Write-Ahead Log)
  Future<void> queueOperation(
    String operation,
    String entityType,
    Map<String, dynamic> payload,
  ) async {
    final db = await LocalDatabase.instance.database;

    final syncItem = {
      'id': _uuid.v4(),
      'operation': operation,
      'entity_type': entityType,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
      'status': 'PENDING',
    };

    await db.insert('sync_queue', syncItem);

    // Optionally trigger a sync immediately in the background
    _triggerSync();
  }

  /// Attempts to flush the sync queue to the remote server
  Future<void> _triggerSync() async {
    final db = await LocalDatabase.instance.database;

    // Get up to 50 pending items
    final pendingItems = await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at ASC',
      limit: 50,
    );

    if (pendingItems.isEmpty) return;

    try {
      // Create batch payload
      final payload = pendingItems
          .map(
            (item) => {
              'sync_id': item['id'],
              'operation': item['operation'],
              'entity_type': item['entity_type'],
              'payload': jsonDecode(item['payload'] as String),
            },
          )
          .toList();

      // Attempt to send to Laravel backend (static method)
      final response = await ApiClient.post('/sync', {'batch': payload});

      if (response.statusCode == 200) {
        // Mark as synced if successful
        final ids = pendingItems.map((e) => e['id']).toList();
        final placeholders = List.filled(ids.length, '?').join(',');

        await db.update(
          'sync_queue',
          {'status': 'COMPLETED'},
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
      } else {
        _incrementRetry(pendingItems);
      }
    } catch (e) {
      _incrementRetry(pendingItems);
    }
  }

  Future<void> _incrementRetry(List<Map<String, dynamic>> items) async {
    final db = await LocalDatabase.instance.database;
    for (var item in items) {
      await db.update(
        'sync_queue',
        {'retry_count': (item['retry_count'] as int) + 1},
        where: 'id = ?',
        whereArgs: [item['id']],
      );
    }
  }

  /// Call this on app startup or via a periodic timer to sync failed items
  Future<void> runPeriodicSync() async {
    await _triggerSync();
  }

  /// Returns the count of pending items in the sync queue
  Future<int> getPendingCount() async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue WHERE status = ?',
      ['PENDING'],
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
