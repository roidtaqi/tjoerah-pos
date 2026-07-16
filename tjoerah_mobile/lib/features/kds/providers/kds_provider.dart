import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../../../core/network/api_client.dart';
import '../models/kitchen_ticket_model.dart';

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

class KdsNotifier extends AsyncNotifier<List<KitchenTicketModel>> {
  PusherChannelsFlutter pusher = PusherChannelsFlutter.getInstance();

  @override
  FutureOr<List<KitchenTicketModel>> build() async {
    final station = ref.watch(kdsStationProvider);

    // Initialize Pusher only once (you might want to move this to a dedicated service)
    _initPusher();

    return _fetchTickets(station);
  }

  Future<void> _initPusher() async {
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
      debugPrint("Pusher Init Error: $e");
    }
  }

  void _onPusherEvent(PusherEvent event) {
    debugPrint("Pusher Event Received: ${event.eventName}");

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
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> ticketsList = data['data'] ?? [];
      return ticketsList
          .map(
            (json) => KitchenTicketModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
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
      }
    } catch (e) {
      // Rollback on failure
      state = previousState;
    }
  }
}
