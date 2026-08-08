import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pusher_client_socket/pusher_client_socket.dart';

import '../../../core/config/realtime_config.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/cash_model.dart';
import '../repositories/cash_repository.dart';

class CashNotifier extends AsyncNotifier<CashOverview> {
  final _repository = CashRepository();
  PusherClient? _pusher;
  PrivateChannel? _channel;
  int? _subscribedOutletId;
  Timer? _refreshDebounce;
  bool _disposeRegistered = false;

  @override
  Future<CashOverview> build() async {
    final user = ref.watch(authProvider).user;
    final outletId = _outletId(user);
    if (RealtimeConfig.enabled) _configureRealtime(outletId);
    if (!_disposeRegistered) {
      _disposeRegistered = true;
      ref.onDispose(_disconnectRealtime);
    }
    return _repository.fetchOverview(outletId);
  }

  Future<void> refresh() async {
    final user = ref.read(authProvider).user;
    state = await AsyncValue.guard(
      () => _repository.fetchOverview(_outletId(user)),
    );
  }

  Future<void> openShift(double openingCash) async {
    final outletId = _outletId(ref.read(authProvider).user);
    await _repository.openShift(outletId: outletId, openingCash: openingCash);
    await refresh();
  }

  Future<void> addMovement({
    required String type,
    required String category,
    required double amount,
    required String note,
    String? photoPath,
  }) async {
    await _repository.addMovement(
      outletId: _outletId(ref.read(authProvider).user),
      type: type,
      category: category,
      amount: amount,
      note: note,
      photoPath: photoPath,
    );
    await refresh();
  }

  Future<void> closeShift({
    required int shiftId,
    required double closingCash,
    String? note,
  }) async {
    await _repository.closeShift(
      shiftId: shiftId,
      closingCash: closingCash,
      note: note,
    );
    await refresh();
  }

  Future<void> emergencyCloseShift({
    required int shiftId,
    required double closingCash,
    required String reason,
  }) async {
    await _repository.emergencyCloseShift(
      shiftId: shiftId,
      closingCash: closingCash,
      reason: reason,
    );
    await refresh();
  }

  void _configureRealtime(int outletId) {
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

      if (_subscribedOutletId != outletId) {
        _channel?.unsubscribe();
        final channel = client.private(
          'cash.outlet.$outletId',
          subscribe: true,
        );
        channel.bind('cash.shift.updated', _onShiftUpdated);
        _channel = channel;
        _subscribedOutletId = outletId;
      }
      if (!client.connected) client.connect();
    } catch (error) {
      debugPrint('Cash realtime initialization failed: $error');
    }
  }

  void _onShiftUpdated(dynamic _) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  void _disconnectRealtime() {
    _refreshDebounce?.cancel();
    try {
      _channel?.unsubscribe();
      _pusher?.disconnect();
    } catch (_) {
      // The socket may already be closed while the provider is disposed.
    }
    _channel = null;
    _pusher = null;
    _subscribedOutletId = null;
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

final cashProvider = AsyncNotifierProvider<CashNotifier, CashOverview>(
  CashNotifier.new,
);

final activeCashShiftIdProvider = Provider<int?>((ref) {
  return ref.watch(cashProvider).value?.currentShift?.id;
});
