import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import '../models/attendance_models.dart';
import 'attendance_offline_queue.dart';

class AttendanceApiException implements Exception {
  const AttendanceApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AttendanceRepository {
  AttendanceRepository({AttendanceOfflineQueue? offlineQueue})
    : _offlineQueue = offlineQueue ?? AttendanceOfflineQueue();

  final AttendanceOfflineQueue _offlineQueue;

  Future<AttendanceContextModel> getContext() async {
    final response = await ApiClient.get('/attendance/context');
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    final context = AttendanceContextModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
    return context.copyWith(
      pendingOfflineCount: await _offlineQueue.pendingCount(),
    );
  }

  Future<AttendanceSubmissionResult> submit({
    required String action,
    required Map<String, dynamic> payload,
    required String photoPath,
  }) async {
    final response = await ApiClient.multipart(
      action == 'check_in' ? '/attendance/check-in' : '/attendance/check-out',
      fields: payload.map(
        (key, value) => MapEntry(key, value == null ? '' : _fieldValue(value)),
      )..removeWhere((key, value) => value.isEmpty),
      photoPath: photoPath,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _apiError(response.body, response.statusCode);
    }

    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return AttendanceSubmissionResult(
      isSuccess: true,
      message: body['message']?.toString() ?? 'Absensi berhasil dicatat.',
      attendance: AttendanceRecord.fromJson(
        Map<String, dynamic>.from(body['attendance'] as Map),
      ),
    );
  }

  Future<void> queue({
    required String action,
    required Map<String, dynamic> payload,
    required String photoPath,
  }) {
    return _offlineQueue.enqueue(
      id: payload['request_id'].toString(),
      action: action,
      payload: payload,
      photoPath: photoPath,
    );
  }

  Future<int> syncPending() async {
    var synced = 0;
    for (final action in await _offlineQueue.pending()) {
      try {
        await submit(
          action: action.action,
          payload: action.payload,
          photoPath: action.photoPath,
        );
        await _offlineQueue.complete(action);
        synced++;
      } on AttendanceApiException catch (error) {
        if (error.statusCode != null && error.statusCode! < 500) {
          await _offlineQueue.fail(action, error.message);
        }
      } catch (_) {
        break;
      }
    }
    return synced;
  }

  Future<List<AttendanceOutlet>> getOutlets() async {
    final response = await ApiClient.get('/attendance/outlets');
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    final rows = decoded is List
        ? decoded
        : (decoded as Map)['data'] as List? ?? const [];
    return rows
        .whereType<Map>()
        .map((row) => AttendanceOutlet.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<AttendanceEmployee>> getEmployees(int outletId) async {
    final response = await ApiClient.get(
      '/employees?outlet_id=$outletId&per_page=100',
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return (body['data'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => AttendanceEmployee.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<AttendancePolicy> getPolicy(int outletId) async {
    final response = await ApiClient.get(
      '/attendance/policy?outlet_id=$outletId',
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return AttendancePolicy.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<AttendancePolicy> updatePolicy(AttendancePolicy policy) async {
    final response = await ApiClient.put('/attendance/policy', policy.toJson());
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return AttendancePolicy.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<(AttendanceSummary, List<AttendanceRecord>)> getReport({
    required int outletId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String status = 'all',
  }) async {
    final response = await ApiClient.get(
      '/attendance/report?outlet_id=$outletId'
      '&date_from=${_dateOnly(dateFrom)}'
      '&date_to=${_dateOnly(dateTo)}'
      '&status=$status&per_page=100',
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final records = Map<String, dynamic>.from(body['records'] as Map);
    return (
      AttendanceSummary.fromJson(
        Map<String, dynamic>.from(body['summary'] as Map),
      ),
      (records['data'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => AttendanceRecord.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
    );
  }

  Future<List<EmployeeScheduleModel>> getSchedules({
    required int outletId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final response = await ApiClient.get(
      '/attendance/schedules?outlet_id=$outletId'
      '&date_from=${_dateOnly(dateFrom)}'
      '&date_to=${_dateOnly(dateTo)}',
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return (jsonDecode(response.body) as List)
        .whereType<Map>()
        .map(
          (row) =>
              EmployeeScheduleModel.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<EmployeeScheduleModel> createSchedule(
    Map<String, dynamic> data,
  ) async {
    final response = await ApiClient.post('/attendance/schedules', data);
    if (response.statusCode != 201) {
      throw _apiError(response.body, response.statusCode);
    }
    return EmployeeScheduleModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<EmployeeScheduleModel> updateSchedule(
    int scheduleId,
    Map<String, dynamic> data,
  ) async {
    final response = await ApiClient.patch(
      '/attendance/schedules/$scheduleId',
      data,
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return EmployeeScheduleModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<void> deleteSchedule(int scheduleId) async {
    final response = await ApiClient.delete(
      '/attendance/schedules/$scheduleId',
    );
    if (response.statusCode != 204) {
      throw _apiError(response.body, response.statusCode);
    }
  }

  Future<AttendanceRecord> reviewAttendance(
    int attendanceId,
    Map<String, dynamic> data,
  ) async {
    final response = await ApiClient.patch(
      '/attendance/records/$attendanceId/review',
      data,
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return AttendanceRecord.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<Uint8List> exportReport({
    required int outletId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String status = 'all',
  }) async {
    final response = await ApiClient.get(
      '/attendance/export?outlet_id=$outletId'
      '&date_from=${_dateOnly(dateFrom)}'
      '&date_to=${_dateOnly(dateTo)}'
      '&status=$status',
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<Uint8List> getPhoto(int attendanceId, String type) async {
    final response = await ApiClient.get(
      '/attendance/$attendanceId/photo/$type',
    );
    if (response.statusCode != 200) {
      throw _apiError(response.body, response.statusCode);
    }
    return response.bodyBytes;
  }

  String _fieldValue(dynamic value) {
    if (value is bool) return value ? '1' : '0';
    return value.toString();
  }

  AttendanceApiException _apiError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final messages in errors.values) {
            if (messages is List && messages.isNotEmpty) {
              return AttendanceApiException(
                messages.first.toString(),
                statusCode: statusCode,
              );
            }
          }
        }
        if (decoded['message'] != null) {
          return AttendanceApiException(
            decoded['message'].toString(),
            statusCode: statusCode,
          );
        }
      }
    } catch (_) {
      // Fall through to the stable user-facing message below.
    }
    return AttendanceApiException(
      'Permintaan absensi belum dapat diproses.',
      statusCode: statusCode,
    );
  }

  String _dateOnly(DateTime value) {
    final date = value.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
