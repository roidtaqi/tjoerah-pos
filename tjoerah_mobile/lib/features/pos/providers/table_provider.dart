import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sync_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/table_models.dart';

class TableState {
  final List<FloorModel> floors;
  final List<DiningTableModel> tables;
  final List<TableSessionModel> sessions;
  final String? selectedFloorId;

  TableState({
    this.floors = const [],
    this.tables = const [],
    this.sessions = const [],
    this.selectedFloorId,
  });

  TableState copyWith({
    List<FloorModel>? floors,
    List<DiningTableModel>? tables,
    List<TableSessionModel>? sessions,
    String? selectedFloorId,
  }) {
    return TableState(
      floors: floors ?? this.floors,
      tables: tables ?? this.tables,
      sessions: sessions ?? this.sessions,
      selectedFloorId: selectedFloorId ?? this.selectedFloorId,
    );
  }
}

class TableNotifier extends AsyncNotifier<TableState> {
  @override
  Future<TableState> build() async {
    return _loadData();
  }

  Future<TableState> _loadData() async {
    final db = await DatabaseHelper.instance.database;
    final floorsData = await db.query('floors', orderBy: 'sort_order ASC');
    final tablesData = await db.query('dining_tables');
    final sessionsData = await db.query('table_sessions');

    final floors = floorsData.map((e) => FloorModel.fromMap(e)).toList();
    final tables = tablesData.map((e) => DiningTableModel.fromMap(e)).toList();
    final sessions = sessionsData
        .map((e) => TableSessionModel.fromMap(e))
        .toList();

    return TableState(
      floors: floors,
      tables: tables,
      sessions: sessions,
      selectedFloorId: floors.isNotEmpty ? floors.first.id : null,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadData());
  }

  void selectFloor(String floorId) {
    if (state.value != null) {
      state = AsyncValue.data(state.value!.copyWith(selectedFloorId: floorId));
    }
  }

  Future<void> syncFromServer() async {
    final synced = await SyncService.syncTables();
    if (!synced) throw StateError('Data meja belum dapat disinkronkan.');
    await refresh();
  }

  Future<FloorModel> createFloor(String name) async {
    final current = state.value;
    final response = await ApiClient.post('/floors', {
      'outlet_id': _outletId(),
      'name': name.trim(),
      'sort_order': current?.floors.length ?? 0,
    });
    if (response.statusCode != 201) throw _apiError(response.body);

    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final floor = FloorModel.fromMap(data);
    final db = await DatabaseHelper.instance.database;
    await db.insert('floors', {
      'id': floor.id,
      'name': floor.name,
      'sort_order': floor.sortOrder,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _reload(selectedFloorId: floor.id);
    return floor;
  }

  Future<void> updateFloor(FloorModel floor, String name) async {
    final response = await ApiClient.patch('/floors/${floor.id}', {
      'name': name.trim(),
    });
    if (response.statusCode != 200) throw _apiError(response.body);

    final db = await DatabaseHelper.instance.database;
    await db.update(
      'floors',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [floor.id],
    );
    await _reload(selectedFloorId: floor.id);
  }

  Future<void> deleteFloor(FloorModel floor) async {
    final current = state.value;
    if (current?.tables.any((table) => table.floorId == floor.id) ?? false) {
      throw StateError('Pindahkan atau hapus semua meja di area ini dahulu.');
    }
    final response = await ApiClient.delete('/floors/${floor.id}');
    if (response.statusCode != 204) throw _apiError(response.body);

    final db = await DatabaseHelper.instance.database;
    await db.delete('floors', where: 'id = ?', whereArgs: [floor.id]);
    await _reload();
  }

  Future<DiningTableModel> createTable({
    required String floorId,
    required String name,
    required int capacity,
    String status = 'available',
  }) async {
    final floorTables =
        state.value?.tables.where((table) => table.floorId == floorId).length ??
        0;
    final x = 24 + (floorTables % 4) * 128;
    final y = 24 + (floorTables ~/ 4) * 96;
    final response = await ApiClient.post('/tables', {
      'outlet_id': _outletId(),
      'floor_id': int.tryParse(floorId) ?? floorId,
      'name': name.trim(),
      'capacity': capacity,
      'status': status,
      'position_x': x,
      'position_y': y,
    });
    if (response.statusCode != 201) throw _apiError(response.body);

    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final table = DiningTableModel.fromMap(data);
    await _saveTable(table);
    await _reload(selectedFloorId: floorId);
    return table;
  }

  Future<void> updateTable({
    required DiningTableModel table,
    required String floorId,
    required String name,
    required int capacity,
    required String status,
  }) async {
    final response = await ApiClient.patch('/tables/${table.id}', {
      'floor_id': int.tryParse(floorId) ?? floorId,
      'name': name.trim(),
      'capacity': capacity,
      'status': status,
    });
    if (response.statusCode != 200) throw _apiError(response.body);

    await _saveTable(
      DiningTableModel(
        id: table.id,
        floorId: floorId,
        name: name.trim(),
        capacity: capacity,
        status: status,
        positionX: table.positionX,
        positionY: table.positionY,
      ),
    );
    await _reload(selectedFloorId: floorId);
  }

  Future<void> deleteTable(DiningTableModel table) async {
    final response = await ApiClient.delete('/tables/${table.id}');
    if (response.statusCode != 204) throw _apiError(response.body);

    final db = await DatabaseHelper.instance.database;
    await db.delete('dining_tables', where: 'id = ?', whereArgs: [table.id]);
    await _reload(selectedFloorId: table.floorId);
  }

  Future<void> updateTablePosition(String tableId, double x, double y) async {
    final selectedFloorId = state.value?.selectedFloorId;
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'dining_tables',
      {'position_x': x, 'position_y': y},
      where: 'id = ?',
      whereArgs: [tableId],
    );

    // We should also sync to backend asynchronously
    try {
      await ApiClient.patch('/tables/$tableId', {
        'position_x': x.round(),
        'position_y': y.round(),
      });
    } catch (_) {}

    await _reload(selectedFloorId: selectedFloorId);
  }

  Future<void> _saveTable(DiningTableModel table) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('dining_tables', {
      'id': table.id,
      'floor_id': table.floorId,
      'name': table.name,
      'capacity': table.capacity,
      'status': table.status,
      'position_x': table.positionX,
      'position_y': table.positionY,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _reload({String? selectedFloorId}) async {
    final result = await _loadData();
    final selected =
        selectedFloorId != null &&
            result.floors.any((floor) => floor.id == selectedFloorId)
        ? selectedFloorId
        : result.selectedFloorId;
    state = AsyncValue.data(result.copyWith(selectedFloorId: selected));
  }

  int _outletId() {
    final user = ref.read(authProvider).user;
    final direct = int.tryParse(user?['outlet_id']?.toString() ?? '');
    if (direct != null) return direct;
    final outlets = user?['outlets'];
    if (outlets is List && outlets.isNotEmpty && outlets.first is Map) {
      final id = int.tryParse((outlets.first as Map)['id']?.toString() ?? '');
      if (id != null) return id;
    }
    throw StateError('Outlet belum dipilih untuk pengaturan meja.');
  }

  Exception _apiError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return Exception(decoded['message']);
      }
    } catch (_) {}
    return Exception('Perubahan meja belum dapat disimpan.');
  }

  Future<String?> openSession(String tableId) async {
    final db = await DatabaseHelper.instance.database;
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    await db.insert('table_sessions', {
      'id': sessionId,
      'table_id': tableId,
      'status': 'open',
      'opened_at': DateTime.now().toIso8601String(),
    });

    await db.update(
      'dining_tables',
      {'status': 'occupied'},
      where: 'id = ?',
      whereArgs: [tableId],
    );

    // Call backend
    try {
      await ApiClient.post('/table-sessions', {'table_id': tableId});
    } catch (_) {}

    await refresh();
    return sessionId;
  }

  Future<void> mergeTable(String sourceTableId, String targetTableId) async {
    // Basic Merge logic: Find active sessions and update
    final db = await DatabaseHelper.instance.database;

    final sourceSessions = await db.query(
      'table_sessions',
      where: 'table_id = ? AND status = ?',
      whereArgs: [sourceTableId, 'open'],
    );
    final targetSessions = await db.query(
      'table_sessions',
      where: 'table_id = ? AND status = ?',
      whereArgs: [targetTableId, 'open'],
    );

    if (sourceSessions.isNotEmpty && targetSessions.isNotEmpty) {
      final sourceSessionId = sourceSessions.first['id'];
      final targetSessionId = targetSessions.first['id'];

      // Close source session, mark as merged
      await db.update(
        'table_sessions',
        {
          'status': 'merged',
          'merged_to_session_id': targetSessionId,
          'closed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sourceSessionId],
      );

      // Release source table
      await db.update(
        'dining_tables',
        {'status': 'available'},
        where: 'id = ?',
        whereArgs: [sourceTableId],
      );

      await refresh();
    }
  }
}

final tableProvider = AsyncNotifierProvider<TableNotifier, TableState>(
  () => TableNotifier(),
);
