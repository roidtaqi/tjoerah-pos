import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../models/transaction_settings.dart';

class TransactionSettingsNotifier extends AsyncNotifier<TransactionSettings> {
  static const _cacheKey = 'transaction_settings';

  @override
  Future<TransactionSettings> build() => _load();

  Future<TransactionSettings> _load() async {
    final outletId = await _resolveOutletId();
    try {
      final response = await ApiClient.get(
        '/transaction-settings?outlet_id=$outletId',
      );
      if (response.statusCode != 200) throw Exception(response.body);
      final decoded = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
      final settings = TransactionSettings.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map),
      );
      await _cache(settings);
      return settings;
    } catch (_) {
      return await _cached(outletId) ??
          TransactionSettings(
            outletId: outletId,
            taxEnabled: true,
            taxRate: 11,
            kdsMode: 'manual',
          );
    }
  }

  Future<String?> updateTax({
    required bool enabled,
    required double rate,
    String? kdsMode,
  }) async {
    final current = state.asData?.value;
    final outletId = current?.outletId ?? await _resolveOutletId();
    try {
      final response = await ApiClient.put('/transaction-settings', {
        'outlet_id': outletId,
        'tax_enabled': enabled,
        'tax_rate': rate,
        'kds_mode': kdsMode ?? current?.kdsMode ?? 'manual',
      });
      final decoded = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
      if (response.statusCode != 200) {
        return decoded['message']?.toString() ??
            'Pengaturan transaksi belum dapat disimpan.';
      }
      final settings = TransactionSettings.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map),
      );
      await _cache(settings);
      state = AsyncValue.data(settings);
      return null;
    } catch (_) {
      return 'Pengaturan transaksi memerlukan koneksi ke server.';
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<int> _resolveOutletId() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('auth_user');
    if (rawUser != null && rawUser.isNotEmpty) {
      final user = Map<String, dynamic>.from(jsonDecode(rawUser) as Map);
      final direct = int.tryParse(user['outlet_id']?.toString() ?? '');
      if (direct != null) return direct;
      final outlets = user['outlets'];
      if (outlets is List && outlets.isNotEmpty && outlets.first is Map) {
        final id = int.tryParse((outlets.first as Map)['id']?.toString() ?? '');
        if (id != null) return id;
      }
    }
    throw StateError('Outlet aktif belum tersedia.');
  }

  Future<void> _cache(TransactionSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(settings.toJson()));
  }

  Future<TransactionSettings?> _cached(int outletId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final settings = TransactionSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      return settings.outletId == outletId ? settings : null;
    } catch (_) {
      return null;
    }
  }
}

final transactionSettingsProvider =
    AsyncNotifierProvider<TransactionSettingsNotifier, TransactionSettings>(
      TransactionSettingsNotifier.new,
    );
