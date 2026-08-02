import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_client_socket/pusher_client_socket.dart';

import '../../../core/config/realtime_config.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';
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
  PusherClient? _pusher;
  final Map<int, PrivateChannel> _channels = {};
  bool _disposeRegistered = false;

  @override
  FutureOr<List<KitchenTicketModel>> build() async {
    final station = ref.watch(kdsStationProvider);
    final user = ref.watch(authProvider.select((auth) => auth.user));
    final outletIds = _outletIds(user);

    if (RealtimeConfig.enabled) {
      _configureRealtime(outletIds);
    }
    if (!_disposeRegistered) {
      _disposeRegistered = true;
      ref.onDispose(_disconnectRealtime);
    }

    return _fetchTickets(station);
  }

  void _configureRealtime(Set<int> outletIds) {
    try {
      final client = _pusher ??= PusherClient(
        options: PusherOptions(
          key: RealtimeConfig.appKey,
          host: RealtimeConfig.host,
          wsPort: RealtimeConfig.port,
          wssPort: RealtimeConfig.port,
          encrypted: RealtimeConfig.encrypted,
          authOptions: PusherAuthOptions(
            RealtimeConfig.authEndpoint,
            headers: () => ApiClient.authHeaders(includeContentType: false),
          ),
          autoConnect: false,
        ),
      );

      for (final removedId in _channels.keys.toSet().difference(outletIds)) {
        _channels.remove(removedId)?.unsubscribe();
      }
      for (final outletId in outletIds.difference(_channels.keys.toSet())) {
        final channel = client.private('kds.outlet.$outletId', subscribe: true);
        channel.bind('order.created', _onOrderCreated);
        channel.bind('ticket.status.updated', _onTicketStatusUpdated);
        _channels[outletId] = channel;
      }

      if (!client.connected) client.connect();
    } catch (error) {
      debugPrint('KDS realtime initialization failed: $error');
    }
  }

  void _onOrderCreated(dynamic eventData) {
    ref.invalidate(kdsOverviewProvider);
    final data = _eventMap(eventData);
    final ticketsData = data['tickets'] as List<dynamic>? ?? const [];
    final newTickets = ticketsData
        .whereType<Map>()
        .map(
          (ticket) =>
              KitchenTicketModel.fromJson(Map<String, dynamic>.from(ticket)),
        )
        .toList();
    final currentStation = ref.read(kdsStationProvider);

    state = state.whenData((currentTickets) {
      final updated = List<KitchenTicketModel>.from(currentTickets);
      for (final newTicket in newTickets) {
        if (newTicket.station == currentStation &&
            !updated.any((ticket) => ticket.id == newTicket.id)) {
          updated.add(newTicket);
        }
      }
      return updated;
    });
  }

  void _onTicketStatusUpdated(dynamic eventData) {
    ref.invalidate(kdsOverviewProvider);
    final data = _eventMap(eventData);
    final rawTicket = data['ticket'];
    if (rawTicket is! Map) return;

    final updatedTicket = KitchenTicketModel.fromJson(
      Map<String, dynamic>.from(rawTicket),
    );
    final currentStation = ref.read(kdsStationProvider);
    if (updatedTicket.station != currentStation) return;

    state = state.whenData((currentTickets) {
      if (updatedTicket.status == 'completed' ||
          updatedTicket.status == 'cancelled') {
        return currentTickets
            .where((ticket) => ticket.id != updatedTicket.id)
            .toList();
      }
      return currentTickets
          .map(
            (ticket) => ticket.id == updatedTicket.id ? updatedTicket : ticket,
          )
          .toList();
    });
  }

  void _disconnectRealtime() {
    try {
      _pusher?.disconnect();
    } catch (_) {
      // The socket may already be closed while the provider is being disposed.
    }
    _channels.clear();
    _pusher = null;
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

Set<int> _outletIds(Map<String, dynamic>? user) {
  final outlets = user?['outlets'];
  if (outlets is! List) return const {};
  return outlets
      .whereType<Map>()
      .map((outlet) => int.tryParse(outlet['id'].toString()))
      .whereType<int>()
      .toSet();
}

Map<String, dynamic> _eventMap(dynamic data) {
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  return const {};
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
