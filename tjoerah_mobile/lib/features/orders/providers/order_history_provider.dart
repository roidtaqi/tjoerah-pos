import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../models/order_history_model.dart';

class OrderHistoryNotifier extends AsyncNotifier<List<OrderHistoryItem>> {
  @override
  Future<List<OrderHistoryItem>> build() => _load();

  Future<List<OrderHistoryItem>> _load() async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query(
      'offline_orders',
      orderBy: 'created_at DESC',
    );
    return rows.map(OrderHistoryItem.fromRow).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }
}

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<OrderHistoryItem>>(
      OrderHistoryNotifier.new,
    );
