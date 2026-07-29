import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../../../core/network/api_client.dart';
import '../models/kitchen_ticket_model.dart';

class ProductionIncidentResult {
  const ProductionIncidentResult({
    required this.isSuccess,
    required this.message,
  });

  final bool isSuccess;
  final String message;
}

class KdsStationNotifier extends Notifier<String> {
  @override
  String build() => 'kitchen';

  void setStation(String station) => state = station;
}

final kdsStationProvider = NotifierProvider<KdsStationNotifier, String>(() {
  return KdsStationNotifier();
});

final kdsNotifierProvider =
    AsyncNotifierProvider<KdsNotifier, List<KitchenTicketModel>>(() {
      return KdsNotifier();
    });

final kdsOverviewProvider = FutureProvider<List<KitchenTicketModel>>((
  ref,
) async {
  final response = await ApiClient.get('/kds/tickets');
  if (response.statusCode != 200) {
    throw Exception('Failed to load ticket overview: ${response.statusCode}');
  }
  return _decodeTickets(response.body);
});

class KdsNotifier extends AsyncNotifier<List<KitchenTicketModel>> {
  PusherChannelsFlutter pusher = PusherChannelsFlutter.getInstance();
  bool _pusherInitialized = false;

  @override
  FutureOr<List<KitchenTicketModel>> build() async {
    final station = ref.watch(kdsStationProvider);

    // Initialize Pusher only once (you might want to move this to a dedicated service)
    _initPusher();

    return _fetchTickets(station);
  }

  Future<void> _initPusher() async {
    if (_pusherInitialized) return;
    _pusherInitialized = true;
    try {
      await pusher.init(
        apiKey: "tjoerah-reverb-key",
        cluster: "mt1",
        onEvent: _onPusherEvent,
        // Uncomment these if targeting local Reverb server:
        // useTLS: false,
        // host: "10.0.2.2", // For Android emulator targeting localhost
        // wsPort: 8080,
      );
      await pusher.subscribe(channelName: "kds.tickets");
      await pusher.connect();
    } catch (e) {
      _pusherInitialized = false;
      debugPrint("Pusher Init Error: $e");
    }
  }

  void _onPusherEvent(PusherEvent event) {
    debugPrint("Pusher Event Received: ${event.eventName}");
    ref.invalidate(kdsOverviewProvider);

    if (event.eventName == 'App\\Domains\\Sales\\Events\\OrderCreated') {
      final data = jsonDecode(event.data);
      final List<dynamic> ticketsData = data['tickets'] ?? [];
      final newTickets = ticketsData
          .map((t) => KitchenTicketModel.fromJson(t as Map<String, dynamic>))
          .toList();

      final currentStation = ref.read(kdsStationProvider);

      // Update state if new tickets belong to the current station
      state = state.whenData((currentTickets) {
        final List<KitchenTicketModel> updated = List.from(currentTickets);
        for (var newTicket in newTickets) {
          if (newTicket.station == currentStation &&
              !updated.any((t) => t.id == newTicket.id)) {
            updated.add(newTicket);
          }
        }
        return updated;
      });
    } else if (event.eventName ==
        'App\\Domains\\KDS\\Events\\TicketStatusUpdated') {
      final data = jsonDecode(event.data);
      final updatedTicket = KitchenTicketModel.fromJson(
        data['ticket'] as Map<String, dynamic>,
      );

      final currentStation = ref.read(kdsStationProvider);

      if (updatedTicket.station == currentStation) {
        state = state.whenData((currentTickets) {
          return currentTickets
              .map((t) => t.id == updatedTicket.id ? updatedTicket : t)
              .toList();
        });
      }
    }
  }

  Future<List<KitchenTicketModel>> _fetchTickets(String station) async {
    final response = await ApiClient.get('/kds/tickets?station=$station');
    if (response.statusCode == 200) {
      return _decodeTickets(response.body);
    } else {
      throw Exception('Failed to load tickets: ${response.statusCode}');
    }
  }

  Future<void> updateTicketStatus(String ticketId, String status) async {
    // Optimistic UI update
    final previousState = state;
    state = state.whenData((tickets) {
      return tickets.map((t) {
        if (t.id == ticketId) {
          return t.copyWith(
            status: status,
            acceptedAt: status == 'accepted' ? DateTime.now() : t.acceptedAt,
            preparingAt: status == 'preparing' ? DateTime.now() : t.preparingAt,
            readyAt: status == 'ready' ? DateTime.now() : t.readyAt,
            completedAt: status == 'completed' ? DateTime.now() : t.completedAt,
          );
        }
        return t;
      }).toList();
    });

    try {
      final response = await ApiClient.post('/kds/tickets/$ticketId/status', {
        'status': status,
      });
      if (response.statusCode != 200) {
        // Rollback on failure
        state = previousState;
      } else {
        ref.invalidate(kdsOverviewProvider);
      }
    } catch (e) {
      // Rollback on failure
      state = previousState;
    }
  }

  Future<ProductionIncidentResult> recordProductionIncident({
    required KitchenTicketModel ticket,
    required KitchenTicketItemModel item,
    required int quantity,
    required String resolution,
    required String reason,
  }) async {
    try {
      final response = await ApiClient.post('/inventory/production-incidents', {
        'order_item_id': item.orderItemId,
        'ticket_id': ticket.id,
        'quantity': quantity,
        'resolution': resolution,
        'reason': reason.trim(),
      });
      final decoded = jsonDecode(response.body);
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final message =
          body['message']?.toString() ??
          'Insiden produksi belum dapat diproses.';
      if (response.statusCode != 201) {
        return ProductionIncidentResult(
          isSuccess: false,
          message: _firstError(body) ?? message,
        );
      }

      final rawTicket = body['ticket'];
      if (rawTicket is Map) {
        final updatedTicket = KitchenTicketModel.fromJson(
          Map<String, dynamic>.from(rawTicket),
        );
        state = state.whenData(
          (tickets) => tickets
              .map(
                (current) =>
                    current.id == updatedTicket.id ? updatedTicket : current,
              )
              .toList(),
        );
      }
      ref.invalidate(kdsOverviewProvider);
      return ProductionIncidentResult(isSuccess: true, message: message);
    } catch (_) {
      return const ProductionIncidentResult(
        isSuccess: false,
        message:
            'Insiden belum dapat disimpan. Periksa koneksi lalu coba lagi.',
      );
    }
  }
}

String? _firstError(Map<String, dynamic> body) {
  final errors = body['errors'];
  if (errors is! Map) return null;
  for (final messages in errors.values) {
    if (messages is List && messages.isNotEmpty) {
      return messages.first.toString();
    }
  }
  return null;
}

List<KitchenTicketModel> _decodeTickets(String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  final tickets = data['data'] as List<dynamic>? ?? const [];
  return tickets
      .map((json) => KitchenTicketModel.fromJson(json as Map<String, dynamic>))
      .toList();
}
