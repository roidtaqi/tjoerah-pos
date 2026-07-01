import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../models/report_models.dart';

class ReportsProvider extends ChangeNotifier {
  List<SalesReportModel> _salesReport = [];
  List<ProductMarginModel> _margins = [];
  List<SystemAlertModel> _alerts = [];
  bool _isLoading = false;
  String? _error;

  List<SalesReportModel> get salesReport => _salesReport;
  List<ProductMarginModel> get margins => _margins;
  List<SystemAlertModel> get alerts => _alerts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Funnel calculations
  double get totalRevenue => _salesReport.fold(0.0, (sum, item) => sum + item.totalSales);
  double get totalCOGS => _salesReport.fold(0.0, (sum, item) => sum + item.cogs);
  double get totalGrossProfit => _salesReport.fold(0.0, (sum, item) => sum + item.grossProfit);
  double get grossMarginPercent => totalRevenue > 0 ? (totalGrossProfit / totalRevenue) * 100 : 0.0;

  ReportsProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final salesResponse = await ApiClient.get('/reports/sales');
      final productsResponse = await ApiClient.get('/reports/products');
      final alertsResponse = await ApiClient.get('/reports/alerts');

      if (salesResponse.statusCode == 200 &&
          productsResponse.statusCode == 200 &&
          alertsResponse.statusCode == 200) {
        
        final List<dynamic> salesData = jsonDecode(salesResponse.body);
        _salesReport = salesData.map((e) => SalesReportModel.fromJson(e as Map<String, dynamic>)).toList();

        final List<dynamic> productsData = jsonDecode(productsResponse.body);
        _margins = productsData.map((e) => ProductMarginModel.fromJson(e as Map<String, dynamic>)).toList();

        final List<dynamic> alertsData = jsonDecode(alertsResponse.body);
        _alerts = alertsData.map((e) => SystemAlertModel.fromJson(e as Map<String, dynamic>)).toList();

        _error = null;
      } else {
        _error = 'Failed to load report data from server.';
      }
    } catch (e) {
      _error = 'Error loading reports: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
