import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/network/api_client.dart';
import '../models/customer_model.dart';

class CustomerNotifier extends AsyncNotifier<List<CustomerModel>> {
  static const _uuid = Uuid();

  @override
  Future<List<CustomerModel>> build() async {
    final local = await _loadLocal();
    try {
      await _syncPending();
      return await _pullRemote();
    } catch (_) {
      return local;
    }
  }

  Future<List<CustomerModel>> _loadLocal() async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query(
      'customers',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(CustomerModel.fromRow).toList();
  }

  Future<List<CustomerModel>> _pullRemote() async {
    final response = await ApiClient.get('/customers');
    if (response.statusCode != 200) throw Exception('Customer fetch failed');

    final decoded = jsonDecode(response.body);
    final rawCustomers = decoded is Map ? decoded['data'] as List? ?? [] : [];
    final customers = rawCustomers
        .whereType<Map>()
        .map((json) => CustomerModel.fromJson(Map<String, dynamic>.from(json)))
        .toList();

    final database = await DatabaseHelper.instance.database;
    await database.transaction((transaction) async {
      for (final customer in customers) {
        await transaction.insert(
          'customers',
          customer.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return _loadLocal();
  }

  Future<bool> addCustomer(CustomerDraft draft) async {
    final temporary = CustomerModel(
      id: _uuid.v4(),
      name: draft.name,
      phone: draft.phone,
      email: draft.email,
      notes: draft.notes,
      totalSpent: 0,
      visitCount: 0,
      isSynced: false,
    );
    final database = await DatabaseHelper.instance.database;
    await database.insert(
      'customers',
      temporary.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    state = AsyncValue.data(await _loadLocal());

    try {
      final response = await ApiClient.post('/customers', draft.toJson());
      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }
      final remote = CustomerModel.fromJson(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
      await database.transaction((transaction) async {
        await transaction.delete(
          'customers',
          where: 'id = ?',
          whereArgs: [temporary.id],
        );
        await transaction.insert(
          'customers',
          remote.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      state = AsyncValue.data(await _loadLocal());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      await _syncPending();
      state = AsyncValue.data(await _pullRemote());
    } catch (_) {
      state = AsyncValue.data(await _loadLocal());
    }
  }

  Future<void> _syncPending() async {
    final database = await DatabaseHelper.instance.database;
    final pending = await database.query(
      'customers',
      where: 'is_synced = 0',
      orderBy: 'updated_at ASC',
    );
    for (final row in pending) {
      final draft = CustomerDraft(
        name: row['name']?.toString() ?? '',
        phone: row['phone']?.toString(),
        email: row['email']?.toString(),
        notes: row['notes']?.toString(),
      );
      final response = await ApiClient.post('/customers', draft.toJson());
      if (response.statusCode != 200 && response.statusCode != 201) break;
      final remote = CustomerModel.fromJson(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
      await database.transaction((transaction) async {
        await transaction.delete(
          'customers',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        await transaction.insert(
          'customers',
          remote.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    }
  }
}

final customerProvider =
    AsyncNotifierProvider<CustomerNotifier, List<CustomerModel>>(
      CustomerNotifier.new,
    );
