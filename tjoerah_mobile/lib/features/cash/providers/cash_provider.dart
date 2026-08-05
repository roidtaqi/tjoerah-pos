import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/cash_model.dart';
import '../repositories/cash_repository.dart';

class CashNotifier extends AsyncNotifier<CashOverview> {
  final _repository = CashRepository();

  @override
  Future<CashOverview> build() async {
    final user = ref.watch(authProvider).user;
    return _repository.fetchOverview(_outletId(user));
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
