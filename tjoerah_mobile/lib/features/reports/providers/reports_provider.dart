import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/database/database_helper.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/report_models.dart';

class ReportsState {
  final List<SalesReportModel> salesReport;
  final List<ProductMarginModel> margins;
  final List<SystemAlertModel> alerts;
  final ShiftReportModel? shiftReport;
  final DateTime startDate;
  final DateTime endDate;
  final bool isLoading;
  final String? error;

  ReportsState({
    this.salesReport = const [],
    this.margins = const [],
    this.alerts = const [],
    this.shiftReport,
    required this.startDate,
    required this.endDate,
    this.isLoading = true,
    this.error,
  });

  double get totalRevenue =>
      salesReport.fold(0.0, (sum, item) => sum + item.totalSales);
  double get totalCOGS => salesReport.fold(0.0, (sum, item) => sum + item.cogs);
  double get totalGrossProfit =>
      salesReport.fold(0.0, (sum, item) => sum + item.grossProfit);
  double get grossMarginPercent =>
      totalRevenue > 0 ? (totalGrossProfit / totalRevenue) * 100 : 0.0;

  ReportsState copyWith({
    List<SalesReportModel>? salesReport,
    List<ProductMarginModel>? margins,
    List<SystemAlertModel>? alerts,
    ShiftReportModel? shiftReport,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ReportsState(
      salesReport: salesReport ?? this.salesReport,
      margins: margins ?? this.margins,
      alerts: alerts ?? this.alerts,
      shiftReport: shiftReport ?? this.shiftReport,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ReportsNotifier extends Notifier<ReportsState> {
  @override
  ReportsState build() {
    final now = DateTime.now();
    // Default to last 7 days for the dashboard
    final startDate = now.subtract(const Duration(days: 7));

    Future.microtask(() {
      loadData();
      generateShiftReport(now);
    });

    return ReportsState(startDate: startDate, endDate: now);
  }

  void setDateRange(DateTime start, DateTime end) {
    state = state.copyWith(startDate: start, endDate: end);
    loadData();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Assuming backend supports date filtering via query params
      final startStr = state.startDate.toIso8601String().split('T').first;
      final endStr = state.endDate.toIso8601String().split('T').first;

      final responses = await Future.wait([
        ApiClient.get('/reports/sales?from=$startStr&to=$endStr'),
        ApiClient.get('/reports/products?from=$startStr&to=$endStr'),
        ApiClient.get('/reports/alerts'),
      ]);
      final salesResponse = responses[0];
      final productsResponse = responses[1];
      final alertsResponse = responses[2];

      if (salesResponse.statusCode == 200 &&
          productsResponse.statusCode == 200 &&
          alertsResponse.statusCode == 200) {
        final List<dynamic> salesData = jsonDecode(salesResponse.body);
        final salesReport = salesData
            .map((e) => SalesReportModel.fromJson(e as Map<String, dynamic>))
            .toList();

        final List<dynamic> productsData = jsonDecode(productsResponse.body);
        final margins = productsData
            .map((e) => ProductMarginModel.fromJson(e as Map<String, dynamic>))
            .toList();

        final List<dynamic> alertsData = jsonDecode(alertsResponse.body);
        final alerts = alertsData
            .map((e) => SystemAlertModel.fromJson(e as Map<String, dynamic>))
            .toList();

        state = state.copyWith(
          salesReport: salesReport,
          margins: margins,
          alerts: alerts,
          isLoading: false,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load report data from server.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error loading reports: $e',
      );
    }
  }

  Future<void> generateShiftReport(DateTime date) async {
    try {
      final outletId = _outletId(ref.read(authProvider).user);
      final dateKey = _dateKey(date);
      final response = await ApiClient.get(
        '/reports/shift?outlet_id=$outletId&date=$dateKey',
      );
      if (response.statusCode == 200) {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(response.body) as Map,
        );
        state = state.copyWith(shiftReport: ShiftReportModel.fromJson(decoded));
        return;
      }
      throw StateError('Laporan shift server belum tersedia.');
    } catch (error) {
      debugPrint('Failed to generate online shift report: $error');
    }

    try {
      final dbResult = await DatabaseHelper.instance.getShiftReport(date);
      final shiftReport = ShiftReportModel.fromLocalDb(date, dbResult);
      state = state.copyWith(shiftReport: shiftReport);
    } catch (error) {
      debugPrint('Failed to generate offline shift report: $error');
    }
  }

  int _outletId(Map<String, dynamic>? user) {
    final direct = int.tryParse(user?['outlet_id']?.toString() ?? '');
    if (direct != null) return direct;
    final outlets = user?['outlets'];
    if (outlets is List && outlets.isNotEmpty && outlets.first is Map) {
      final id = int.tryParse((outlets.first as Map)['id']?.toString() ?? '');
      if (id != null) return id;
    }
    throw StateError('Outlet aktif belum tersedia.');
  }
}

final reportsProvider = NotifierProvider<ReportsNotifier, ReportsState>(() {
  return ReportsNotifier();
});

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
