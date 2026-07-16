import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../models/outlet_summary_model.dart';

class OutletNotifier extends AsyncNotifier<List<OutletSummaryModel>> {
  static const _cacheKey = 'outlet_summaries';

  @override
  Future<List<OutletSummaryModel>> build() => _load();

  Future<List<OutletSummaryModel>> _load() async {
    try {
      final responses = await Future.wait([
        ApiClient.get('/outlets'),
        ApiClient.get('/reports/outlets'),
      ]);
      if (responses.any((response) => response.statusCode != 200)) {
        throw Exception('Outlet fetch failed');
      }

      final outlets = (jsonDecode(responses[0].body) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final performance = (jsonDecode(responses[1].body) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final performanceById = {
        for (final item in performance) item['outlet_id']?.toString(): item,
      };

      final summaries = outlets.map((outlet) {
        final metrics = performanceById[outlet['id']?.toString()];
        return OutletSummaryModel.fromJson({...outlet, ...?metrics});
      }).toList();
      await _cache(summaries);
      return summaries;
    } catch (_) {
      final cached = await _loadCache();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> _cache(List<OutletSummaryModel> outlets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(outlets.map((outlet) => outlet.toJson()).toList()),
    );
  }

  Future<List<OutletSummaryModel>> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (item) =>
                OutletSummaryModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }
}

final outletProvider =
    AsyncNotifierProvider<OutletNotifier, List<OutletSummaryModel>>(
      OutletNotifier.new,
    );
