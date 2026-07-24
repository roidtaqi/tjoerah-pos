import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_models.dart';
import '../repositories/attendance_repository.dart';
import 'attendance_provider.dart';

class AttendanceAdminState {
  const AttendanceAdminState({
    required this.outlets,
    required this.selectedOutlet,
    required this.policy,
    required this.employees,
    required this.summary,
    required this.records,
    required this.schedules,
    required this.dateFrom,
    required this.dateTo,
    this.status = 'all',
  });

  final List<AttendanceOutlet> outlets;
  final AttendanceOutlet selectedOutlet;
  final AttendancePolicy policy;
  final List<AttendanceEmployee> employees;
  final AttendanceSummary summary;
  final List<AttendanceRecord> records;
  final List<EmployeeScheduleModel> schedules;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String status;

  AttendanceAdminState copyWith({
    AttendanceOutlet? selectedOutlet,
    AttendancePolicy? policy,
    List<AttendanceEmployee>? employees,
    AttendanceSummary? summary,
    List<AttendanceRecord>? records,
    List<EmployeeScheduleModel>? schedules,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
  }) {
    return AttendanceAdminState(
      outlets: outlets,
      selectedOutlet: selectedOutlet ?? this.selectedOutlet,
      policy: policy ?? this.policy,
      employees: employees ?? this.employees,
      summary: summary ?? this.summary,
      records: records ?? this.records,
      schedules: schedules ?? this.schedules,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      status: status ?? this.status,
    );
  }
}

class AttendanceAdminResult {
  const AttendanceAdminResult(this.isSuccess, this.message);

  final bool isSuccess;
  final String message;
}

class AttendanceAdminNotifier extends AsyncNotifier<AttendanceAdminState> {
  AttendanceRepository get _repository =>
      ref.read(attendanceRepositoryProvider);

  @override
  Future<AttendanceAdminState> build() async {
    final outlets = await _repository.getOutlets();
    if (outlets.isEmpty) {
      throw const AttendanceApiException(
        'Belum ada outlet yang dapat dikelola.',
      );
    }
    final now = DateTime.now();
    final dateFrom = DateTime(now.year, now.month, 1);
    final dateTo = DateTime(now.year, now.month + 1, 0);
    return _load(
      outlets: outlets,
      outlet: outlets.first,
      dateFrom: dateFrom,
      dateTo: dateTo,
      status: 'all',
    );
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(
        await _load(
          outlets: current.outlets,
          outlet: current.selectedOutlet,
          dateFrom: current.dateFrom,
          dateTo: current.dateTo,
          status: current.status,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> selectOutlet(AttendanceOutlet outlet) async {
    final current = state.requireValue;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _load(
        outlets: current.outlets,
        outlet: outlet,
        dateFrom: current.dateFrom,
        dateTo: current.dateTo,
        status: current.status,
      ),
    );
  }

  Future<void> setFilters({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
  }) async {
    final current = state.requireValue;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _load(
        outlets: current.outlets,
        outlet: current.selectedOutlet,
        dateFrom: dateFrom ?? current.dateFrom,
        dateTo: dateTo ?? current.dateTo,
        status: status ?? current.status,
      ),
    );
  }

  Future<AttendanceAdminResult> savePolicy(AttendancePolicy policy) async {
    try {
      final saved = await _repository.updatePolicy(policy);
      final current = state.requireValue;
      state = AsyncValue.data(current.copyWith(policy: saved));
      return const AttendanceAdminResult(
        true,
        'Pengaturan absensi berhasil disimpan.',
      );
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(
        false,
        'Pengaturan belum dapat disimpan. Periksa koneksi server.',
      );
    }
  }

  Future<AttendanceAdminResult> saveSchedule(
    Map<String, dynamic> data, {
    int? scheduleId,
  }) async {
    try {
      if (scheduleId == null) {
        await _repository.createSchedule(data);
      } else {
        await _repository.updateSchedule(scheduleId, data);
      }
      await refresh();
      return AttendanceAdminResult(
        true,
        scheduleId == null
            ? 'Jadwal berhasil ditambahkan.'
            : 'Jadwal berhasil diperbarui.',
      );
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(
        false,
        'Jadwal belum dapat disimpan. Periksa koneksi server.',
      );
    }
  }

  Future<AttendanceAdminResult> deleteSchedule(
    EmployeeScheduleModel schedule,
  ) async {
    try {
      await _repository.deleteSchedule(schedule.id);
      await refresh();
      return const AttendanceAdminResult(true, 'Jadwal berhasil dihapus.');
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(false, 'Jadwal belum dapat dihapus.');
    }
  }

  Future<AttendanceAdminResult> review(
    AttendanceRecord attendance,
    Map<String, dynamic> data,
  ) async {
    try {
      await _repository.reviewAttendance(attendance.id, data);
      await refresh();
      return const AttendanceAdminResult(
        true,
        'Pemeriksaan absensi berhasil disimpan.',
      );
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(
        false,
        'Pemeriksaan belum dapat disimpan.',
      );
    }
  }

  Future<AttendanceAdminState> _load({
    required List<AttendanceOutlet> outlets,
    required AttendanceOutlet outlet,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String status,
  }) async {
    final results = await Future.wait([
      _repository.getPolicy(outlet.id),
      _repository.getEmployees(outlet.id),
      _repository.getReport(
        outletId: outlet.id,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
      ),
      _repository.getSchedules(
        outletId: outlet.id,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ),
    ]);
    final report = results[2] as (AttendanceSummary, List<AttendanceRecord>);

    return AttendanceAdminState(
      outlets: outlets,
      selectedOutlet: outlet,
      policy: results[0] as AttendancePolicy,
      employees: results[1] as List<AttendanceEmployee>,
      summary: report.$1,
      records: report.$2,
      schedules: results[3] as List<EmployeeScheduleModel>,
      dateFrom: dateFrom,
      dateTo: dateTo,
      status: status,
    );
  }
}

final attendanceAdminProvider =
    AsyncNotifierProvider<AttendanceAdminNotifier, AttendanceAdminState>(
      AttendanceAdminNotifier.new,
    );
