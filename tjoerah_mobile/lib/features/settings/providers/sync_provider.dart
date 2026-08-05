import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/sync_service.dart';
import '../../customers/providers/customer_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../orders/providers/order_history_provider.dart';
import '../../pos/repositories/order_repository.dart';

class SyncState {
  const SyncState({
    this.pendingCount = 0,
    this.pendingOrders = 0,
    this.pendingInventory = 0,
    this.pendingCustomers = 0,
    this.isSyncing = false,
    this.lastSyncedAt,
    this.error,
  });

  final int pendingCount;
  final int pendingOrders;
  final int pendingInventory;
  final int pendingCustomers;
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final String? error;

  String get pendingSummary {
    final parts = <String>[
      if (pendingOrders > 0) '$pendingOrders pesanan',
      if (pendingInventory > 0) '$pendingInventory inventori',
      if (pendingCustomers > 0) '$pendingCustomers pelanggan',
    ];
    return parts.join(' • ');
  }
}

class SyncNotifier extends Notifier<SyncState> {
  static const _lastSyncKey = 'last_sync_at';
  Timer? _timer;

  @override
  SyncState build() {
    Future.microtask(_fetchStatus);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchStatus());
    ref.onDispose(() => _timer?.cancel());
    return const SyncState();
  }

  Future<void> _fetchStatus({String? error}) async {
    try {
      final database = await DatabaseHelper.instance.database;
      final counts = await Future.wait([
        _count(database, 'offline_orders', 'status = ?', ['pending']),
        _count(database, 'offline_inventory_incidents', 'status = ?', [
          'pending',
        ]),
        _count(database, 'customers', 'is_synced = 0', const []),
      ]);
      final prefs = await SharedPreferences.getInstance();
      state = SyncState(
        pendingCount: counts.fold(0, (sum, count) => sum + count),
        pendingOrders: counts[0],
        pendingInventory: counts[1],
        pendingCustomers: counts[2],
        isSyncing: state.isSyncing,
        lastSyncedAt: DateTime.tryParse(prefs.getString(_lastSyncKey) ?? ''),
        error: error,
      );
    } catch (_) {
      state = SyncState(
        pendingCount: state.pendingCount,
        pendingOrders: state.pendingOrders,
        pendingInventory: state.pendingInventory,
        pendingCustomers: state.pendingCustomers,
        isSyncing: state.isSyncing,
        lastSyncedAt: state.lastSyncedAt,
        error: error ?? state.error,
      );
    }
  }

  Future<int> _count(
    Database database,
    String table,
    String where,
    List<Object?> args,
  ) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS total FROM $table WHERE $where',
      args,
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> forceSync() async {
    if (state.isSyncing) return;
    state = SyncState(
      pendingCount: state.pendingCount,
      pendingOrders: state.pendingOrders,
      pendingInventory: state.pendingInventory,
      pendingCustomers: state.pendingCustomers,
      isSyncing: true,
      lastSyncedAt: state.lastSyncedAt,
    );

    String? error;
    try {
      final customerError = await ref
          .read(customerProvider.notifier)
          .syncPendingCustomers();
      final orderResult = await OrderRepository().syncOfflineOrders();
      final inventoryError = await ref
          .read(inventoryProvider.notifier)
          .syncPendingIncidents();
      final referenceResults = await Future.wait([
        SyncService.syncCatalog(),
        SyncService.syncInventory(),
        SyncService.syncTables(),
      ]);
      await ref.read(customerProvider.notifier).refresh();
      ref.invalidate(orderHistoryProvider);
      final errors = <String>[
        if (!orderResult.isComplete)
          orderResult.error == null
              ? '${orderResult.pendingCount} pesanan masih menunggu sinkron.'
              : '${orderResult.pendingCount} pesanan masih menunggu. '
                    '${orderResult.error}',
      ];
      if (inventoryError != null) errors.add(inventoryError);
      if (customerError != null) errors.add(customerError);
      if (referenceResults.any((success) => !success)) {
        const labels = ['katalog', 'inventori', 'meja'];
        final failed = <String>[
          for (var index = 0; index < referenceResults.length; index++)
            if (!referenceResults[index]) labels[index],
        ];
        errors.add('Data ${failed.join(', ')} belum berhasil diperbarui.');
      }
      if (errors.isNotEmpty) {
        error = errors.join(' ');
      } else {
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastSyncKey, now.toIso8601String());
      }
    } catch (_) {
      error = 'Koneksi belum tersedia. Antrean tetap tersimpan.';
    }

    state = SyncState(
      pendingCount: state.pendingCount,
      pendingOrders: state.pendingOrders,
      pendingInventory: state.pendingInventory,
      pendingCustomers: state.pendingCustomers,
      isSyncing: false,
      lastSyncedAt: state.lastSyncedAt,
      error: error,
    );
    await _fetchStatus(error: error);
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
