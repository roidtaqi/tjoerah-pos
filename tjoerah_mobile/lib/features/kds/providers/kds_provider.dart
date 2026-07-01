import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../models/kitchen_ticket_model.dart';

class KdsProvider extends ChangeNotifier {
  List<KitchenTicketModel> _tickets = [];
  bool _isLoading = false;
  String? _error;
  Timer? _refreshTimer;
  String _selectedStation = 'kitchen';

  List<KitchenTicketModel> get tickets => _tickets;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedStation => _selectedStation;

  KdsProvider() {
    fetchTickets();
    _startPeriodicRefresh();
  }

  void setStation(String station) {
    _selectedStation = station;
    fetchTickets();
    notifyListeners();
  }

  Future<void> fetchTickets() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiClient.get('/kds/tickets?station=$_selectedStation');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> ticketsList = data['data'] ?? [];
        _tickets = ticketsList.map((json) => KitchenTicketModel.fromJson(json as Map<String, dynamic>)).toList();
        _error = null;
      } else {
        _error = 'Failed to load tickets: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'Error loading tickets: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateTicketStatus(String ticketId, String status) async {
    try {
      // Optimistic UI update
      final ticketIndex = _tickets.indexWhere((t) => t.id == ticketId);
      if (ticketIndex != -1) {
        final original = _tickets[ticketIndex];
        _tickets[ticketIndex] = original.copyWith(
          status: status,
          acceptedAt: status == 'accepted' ? DateTime.now() : original.acceptedAt,
          preparingAt: status == 'preparing' ? DateTime.now() : original.preparingAt,
          readyAt: status == 'ready' ? DateTime.now() : original.readyAt,
          completedAt: status == 'completed' ? DateTime.now() : original.completedAt,
        );
        notifyListeners();
      }

      final response = await ApiClient.post('/kds/tickets/$ticketId/status', {'status': status});
      if (response.statusCode != 200) {
        // Rollback on failure
        fetchTickets();
      }
    } catch (e) {
      fetchTickets();
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchTickets();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
