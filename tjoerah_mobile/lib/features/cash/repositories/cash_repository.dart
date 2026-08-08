import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../models/cash_model.dart';

class CashRepository {
  Future<CashOverview> fetchOverview(int outletId) async {
    final response = await ApiClient.get('/cash/overview?outlet_id=$outletId');
    final body = _body(response.body);
    if (response.statusCode != 200) throw StateError(_message(body));
    return CashOverview.fromJson(body);
  }

  Future<void> openShift({
    required int outletId,
    required double openingCash,
  }) async {
    final response = await ApiClient.post('/cash/sessions/open', {
      'outlet_id': outletId,
      'opening_cash': openingCash,
    });
    final body = _body(response.body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_message(body));
    }
  }

  Future<void> addMovement({
    required int outletId,
    required String type,
    required String category,
    required double amount,
    required String note,
    String? photoPath,
  }) async {
    final fields = {
      'outlet_id': '$outletId',
      'type': type,
      'category': category,
      'amount': '$amount',
      'note': note,
      'client_reference': DateTime.now().microsecondsSinceEpoch.toString(),
    };
    final response = photoPath == null
        ? await ApiClient.post('/cash/movements', fields)
        : await ApiClient.multipart(
            '/cash/movements',
            fields: fields,
            photoPath: photoPath,
          );
    final body = _body(response.body);
    if (response.statusCode != 201) throw StateError(_message(body));
  }

  Future<void> closeShift({
    required int shiftId,
    required double closingCash,
    String? note,
  }) async {
    final response = await ApiClient.post('/cash/sessions/$shiftId/close', {
      'closing_cash': closingCash,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    final body = _body(response.body);
    if (response.statusCode != 200) throw StateError(_message(body));
  }

  Future<void> emergencyCloseShift({
    required int shiftId,
    required double closingCash,
    required String reason,
  }) async {
    final response = await ApiClient.post(
      '/cash/sessions/$shiftId/emergency-close',
      {'closing_cash': closingCash, 'reason': reason.trim()},
    );
    final body = _body(response.body);
    if (response.statusCode != 200) throw StateError(_message(body));
  }

  Map<String, dynamic> _body(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _message(Map<String, dynamic> body) {
    final errors = body['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
      }
    }
    return body['message']?.toString() ?? 'Data kas belum dapat disimpan.';
  }
}
