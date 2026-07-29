import 'dart:typed_data';

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
    required this.shifts,
    required this.dateFrom,
    required this.dateTo,
    this.status = 'all',
    this.isRefreshing = false,
  });

  final List<AttendanceOutlet> outlets;
  final AttendanceOutlet selectedOutlet;
  final AttendancePolicy policy;
  final List<AttendanceEmployee> employees;
  final AttendanceSummary summary;
  final List<AttendanceRecord> records;
  final List<EmployeeScheduleModel> schedules;
  final List<AttendanceShiftModel> shifts;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String status;
  final bool isRefreshing;

  AttendanceAdminState copyWith({
    AttendanceOutlet? selectedOutlet,
    AttendancePolicy? policy,
    List<AttendanceEmployee>? employees,
    AttendanceSummary? summary,
    List<AttendanceRecord>? records,
    List<EmployeeScheduleModel>? schedules,
    List<AttendanceShiftModel>? shifts,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
    bool? isRefreshing,
  }) {
    return AttendanceAdminState(
      outlets: outlets,
      selectedOutlet: selectedOutlet ?? this.selectedOutlet,
      policy: policy ?? this.policy,
      employees: employees ?? this.employees,
      summary: summary ?? this.summary,
      records: records ?? this.records,
      schedules: schedules ?? this.schedules,
      shifts: shifts ?? this.shifts,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      status: status ?? this.status,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class AttendanceAdminResult {
  const AttendanceAdminResult(this.isSuccess, this.message);

  final bool isSuccess;
  final String message;
}

class AttendanceAdminNotifier extends AsyncNotifier<AttendanceAdminState> {
  int _loadGeneration = 0;

  AttendanceRepository get _repository =>
      ref.read(attendanceRepositoryProvider);

  @override
  Future<AttendanceAdminState> build() async {
    final now = DateTime.now();
    final dateFrom = DateTime(now.year, now.month, 1);
    final dateTo = DateTime(now.year, now.month + 1, 0);
    return _load(dateFrom: dateFrom, dateTo: dateTo, status: 'all');
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    await _reload(
      current,
      outlet: current.selectedOutlet,
      dateFrom: current.dateFrom,
      dateTo: current.dateTo,
      status: current.status,
    );
  }

  Future<void> selectOutlet(AttendanceOutlet outlet) async {
    final current = state.requireValue;
    await _reload(
      current,
      outlet: outlet,
      dateFrom: current.dateFrom,
      dateTo: current.dateTo,
      status: current.status,
    );
  }

  Future<void> setFilters({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
  }) async {
    final current = state.requireValue;
    await _reload(
      current,
      outlet: current.selectedOutlet,
      dateFrom: dateFrom ?? current.dateFrom,
      dateTo: dateTo ?? current.dateTo,
      status: status ?? current.status,
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

  Future<AttendanceAdminResult> importSchedules({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final current = state.requireValue;
      final count = await _repository.importSchedules(
        outletId: current.selectedOutlet.id,
        bytes: bytes,
        filename: filename,
      );
      await refresh();
      return AttendanceAdminResult(true, '$count jadwal berhasil diimpor.');
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(
        false,
        'Jadwal belum dapat diimpor. Periksa file dan koneksi server.',
      );
    }
  }

  Future<AttendanceAdminResult> saveAttendanceShift(
    AttendanceShiftModel shift, {
    required bool isNew,
  }) async {
    try {
      if (isNew) {
        await _repository.createAttendanceShift(shift);
      } else {
        await _repository.updateAttendanceShift(shift);
      }
      await refresh();
      return AttendanceAdminResult(
        true,
        isNew ? 'Shift berhasil ditambahkan.' : 'Shift berhasil diperbarui.',
      );
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(
        false,
        'Shift belum dapat disimpan. Periksa koneksi server.',
      );
    }
  }

  Future<AttendanceAdminResult> deleteAttendanceShift(
    AttendanceShiftModel shift,
  ) async {
    try {
      await _repository.deleteAttendanceShift(shift.id);
      await refresh();
      return const AttendanceAdminResult(true, 'Shift berhasil dihapus.');
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(false, 'Shift belum dapat dihapus.');
    }
  }

  Future<AttendanceAdminResult> assignAttendanceShifts(
    Map<int, int?> assignments,
  ) async {
    try {
      final current = state.requireValue;
      final employees = await _repository.assignAttendanceShifts(
        outletId: current.selectedOutlet.id,
        assignments: assignments,
      );
      state = AsyncValue.data(current.copyWith(employees: employees));
      await refresh();
      return const AttendanceAdminResult(
        true,
        'Shift karyawan berhasil diperbarui.',
      );
    } on AttendanceApiException catch (error) {
      return AttendanceAdminResult(false, error.message);
    } catch (_) {
      return const AttendanceAdminResult(
        false,
        'Penugasan shift belum dapat disimpan.',
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
    List<AttendanceOutlet>? outlets,
    AttendanceOutlet? outlet,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String status,
  }) async {
    try {
      final snapshot = await _repository.getAdminContext(
        outletId: outlet?.id,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
      );
      return AttendanceAdminState(
        outlets: snapshot.outlets,
        selectedOutlet: snapshot.selectedOutlet,
        policy: snapshot.policy,
        employees: snapshot.employees,
        summary: snapshot.summary,
        records: snapshot.records,
        schedules: snapshot.schedules,
        shifts: snapshot.shifts,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
      );
    } on AttendanceApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }

    final availableOutlets = outlets ?? await _repository.getOutlets();
    if (availableOutlets.isEmpty) {
      throw const AttendanceApiException(
        'Belum ada outlet yang dapat dikelola.',
      );
    }
    final selectedOutlet = outlet ?? availableOutlets.first;
    final results = await Future.wait([
      _repository.getPolicy(selectedOutlet.id),
      _repository.getEmployees(selectedOutlet.id),
      _repository.getReport(
        outletId: selectedOutlet.id,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
      ),
      _repository.getSchedules(
        outletId: selectedOutlet.id,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ),
      _repository.getAttendanceShifts(selectedOutlet.id),
    ]);
    final report = results[2] as (AttendanceSummary, List<AttendanceRecord>);

    return AttendanceAdminState(
      outlets: availableOutlets,
      selectedOutlet: selectedOutlet,
      policy: results[0] as AttendancePolicy,
      employees: results[1] as List<AttendanceEmployee>,
      summary: report.$1,
      records: report.$2,
      schedules: results[3] as List<EmployeeScheduleModel>,
      shifts: results[4] as List<AttendanceShiftModel>,
      dateFrom: dateFrom,
      dateTo: dateTo,
      status: status,
    );
  }

  Future<void> _reload(
    AttendanceAdminState current, {
    required AttendanceOutlet outlet,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String status,
  }) async {
    final generation = ++_loadGeneration;
    state = AsyncValue.data(current.copyWith(isRefreshing: true));
    try {
      final next = await _load(
        outlets: current.outlets,
        outlet: outlet,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
      );
      if (generation == _loadGeneration) {
        state = AsyncValue.data(next);
      }
    } catch (_) {
      if (generation == _loadGeneration) {
        state = AsyncValue.data(current.copyWith(isRefreshing: false));
      }
    }
  }
}

final attendanceAdminProvider =
    AsyncNotifierProvider<AttendanceAdminNotifier, AttendanceAdminState>(
      AttendanceAdminNotifier.new,
    );
