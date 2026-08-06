import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/attendance/models/attendance_models.dart';
import 'package:tjoerah_mobile/features/attendance/providers/attendance_admin_provider.dart';
import 'package:tjoerah_mobile/features/attendance/providers/attendance_provider.dart';
import 'package:tjoerah_mobile/features/attendance/screens/attendance_admin_screen.dart';
import 'package:tjoerah_mobile/features/attendance/screens/attendance_screen.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';

void main() {
  testWidgets('employee sees schedule, action, and recent attendance', (
    tester,
  ) async {
    await _render(
      tester,
      ProviderScope(
        overrides: [
          attendanceProvider.overrideWith(_PreviewAttendanceNotifier.new),
        ],
        child: const AttendanceScreen(),
      ),
    );

    expect(find.text('Absensi'), findsOneWidget);
    expect(find.text('Rani Kasir'), findsOneWidget);
    expect(find.text('Tjoerah Utama - Kasir'), findsOneWidget);
    expect(find.text('Absen masuk'), findsOneWidget);
    expect(find.text('Jadwal mendatang'), findsOneWidget);
    expect(find.text('Ajukan perubahan'), findsOneWidget);
    expect(find.text('Status pengajuan'), findsOneWidget);
    expect(find.text('Terlambat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner sees attendance report and management tabs', (
    tester,
  ) async {
    await _render(
      tester,
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _AttendanceAuthNotifier('owner')),
          attendanceAdminProvider.overrideWith(
            _PreviewAttendanceAdminNotifier.new,
          ),
        ],
        child: const AttendanceAdminScreen(),
      ),
    );

    expect(find.text('Manajemen absensi'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Roster'), findsOneWidget);
    expect(find.text('Permintaan'), findsOneWidget);
    expect(find.text('Shift'), findsOneWidget);
    expect(find.text('Kebijakan'), findsOneWidget);
    expect(find.text('Hadir'), findsOneWidget);
    expect(find.text('Rani Kasir'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Roster'));
    await tester.pumpAndSettle();
    expect(find.text('Terbitkan'), findsOneWidget);
    expect(find.byTooltip('Unduh template jadwal'), findsOneWidget);
    expect(find.byTooltip('Impor jadwal CSV'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Terbitkan'));
    await tester.pumpAndSettle();
    expect(find.text('Terbitkan jadwal yang sudah diisi?'), findsOneWidget);
    expect(find.textContaining('1 jadwal draft'), findsOneWidget);
    expect(
      find.textContaining('Hari yang belum diisi tetap kosong'),
      findsOneWidget,
    );
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Permintaan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permintaan'));
    await tester.pumpAndSettle();
    expect(find.text('Butuh tukar jadwal keluarga'), findsOneWidget);
    expect(find.text('Tinjau & setujui'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shift'));
    await tester.pumpAndSettle();
    expect(find.text('Shift absensi'), findsOneWidget);
    expect(find.text('Shift Pagi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Kebijakan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kebijakan'));
    await tester.pumpAndSettle();
    expect(find.text('Jam kerja cadangan'), findsOneWidget);
    expect(find.text('Simpan kebijakan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cashier cannot open attendance management', (tester) async {
    await _render(
      tester,
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _AttendanceAuthNotifier('cashier')),
        ],
        child: const AttendanceAdminScreen(),
      ),
    );

    expect(find.text('Akses dibatasi'), findsOneWidget);
    expect(find.text('Kebijakan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attendance screens fit the SM T220 landscape viewport', (
    tester,
  ) async {
    await _render(
      tester,
      ProviderScope(
        overrides: [
          attendanceProvider.overrideWith(_PreviewAttendanceNotifier.new),
        ],
        child: const AttendanceScreen(),
      ),
      size: const Size(1007, 553),
    );
    expect(find.text('Absen masuk'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _AttendanceAuthNotifier('owner')),
          attendanceAdminProvider.overrideWith(
            _PreviewAttendanceAdminNotifier.new,
          ),
        ],
        child: const AttendanceAdminScreen(),
      ),
      size: const Size(1007, 553),
    );
    expect(find.text('Manajemen absensi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final tab in ['Roster', 'Permintaan', 'Shift', 'Kebijakan']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Attendance tab $tab overflowed on the SM T220.',
      );
    }
  });
}

Future<void> _render(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: child));
  await tester.pump();
}

class _AttendanceAuthNotifier extends AuthNotifier {
  _AttendanceAuthNotifier(this.role);

  final String role;

  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {'name': 'Test User', 'role': role},
  );
}

class _PreviewAttendanceNotifier extends AttendanceNotifier {
  @override
  Future<AttendanceContextModel> build() async => _context;
}

class _PreviewAttendanceAdminNotifier extends AttendanceAdminNotifier {
  @override
  Future<AttendanceAdminState> build() async => _adminState;
}

const _employee = AttendanceEmployee(
  id: 1,
  name: 'Rani Kasir',
  position: 'Kasir',
  outletId: 1,
  attendanceShiftId: 1,
  attendanceShift: _shift,
);

const _outlet = AttendanceOutlet(id: 1, name: 'Tjoerah Utama');

const _shift = AttendanceShiftModel(
  id: 1,
  outletId: 1,
  name: 'Shift Pagi',
  startTime: '07:30',
  lateAfterTime: '07:45',
  endTime: '15:30',
  employeesCount: 1,
);

const _policy = AttendancePolicy(
  outletId: 1,
  latitude: -8.65,
  longitude: 115.21,
);

final _record = AttendanceRecord(
  id: 1,
  employeeId: 1,
  outletId: 1,
  workDate: DateTime(2026, 7, 24),
  scheduledStartAt: DateTime.utc(2026, 7, 24),
  scheduledLateAfterAt: DateTime.utc(2026, 7, 24, 0, 15),
  scheduledEndAt: DateTime.utc(2026, 7, 24, 9),
  checkInAt: DateTime.utc(2026, 7, 24, 0, 20),
  punctualityStatus: 'late',
  lateMinutes: 10,
  employee: _employee,
  outlet: _outlet,
  attendanceShift: _shift,
);

final _context = AttendanceContextModel(
  employee: _employee,
  outlet: _outlet,
  policy: _policy,
  attendanceShift: _shift,
  scheduledStartAt: DateTime.utc(2026, 7, 24),
  scheduledLateAfterAt: DateTime.utc(2026, 7, 24, 0, 15),
  scheduledEndAt: DateTime.utc(2026, 7, 24, 9),
  serverTime: DateTime.utc(2026, 7, 24),
  recentAttendance: [_record],
  availableShifts: const [_shift],
  upcomingSchedules: [_publishedSchedule],
  changeRequests: [_changeRequest],
);

final _adminState = AttendanceAdminState(
  outlets: const [_outlet],
  selectedOutlet: _outlet,
  policy: _policy,
  employees: const [_employee],
  summary: const AttendanceSummary(
    total: 1,
    late: 1,
    pendingReview: 1,
    lateMinutes: 10,
  ),
  records: [_record],
  schedules: [_draftSchedule],
  shifts: const [_shift],
  changeRequests: [_changeRequest],
  dateFrom: DateTime(2026, 7, 1),
  dateTo: DateTime(2026, 7, 31),
);

final _publishedSchedule = EmployeeScheduleModel(
  id: 11,
  employeeId: 1,
  outletId: 1,
  workDate: DateTime(2026, 8, 3),
  startAt: DateTime.utc(2026, 8, 2, 23, 30),
  lateAfterAt: DateTime.utc(2026, 8, 2, 23, 45),
  endAt: DateTime.utc(2026, 8, 3, 7, 30),
  shiftName: 'Shift Pagi',
  status: 'scheduled',
  employee: _employee,
  attendanceShiftId: 1,
  attendanceShift: _shift,
);

final _draftSchedule = EmployeeScheduleModel(
  id: 12,
  employeeId: 1,
  outletId: 1,
  workDate: DateTime(2026, 7, 1),
  startAt: DateTime.utc(2026, 6, 30, 23, 30),
  lateAfterAt: DateTime.utc(2026, 6, 30, 23, 45),
  endAt: DateTime.utc(2026, 7, 1, 7, 30),
  shiftName: 'Shift Pagi',
  status: 'scheduled',
  employee: _employee,
  attendanceShiftId: 1,
  attendanceShift: _shift,
  publicationStatus: 'draft',
);

final _changeRequest = ShiftChangeRequestModel(
  id: 21,
  employeeId: 1,
  outletId: 1,
  requestedWorkDate: DateTime(2026, 8, 3),
  requestedStatus: 'off',
  reason: 'Butuh tukar jadwal keluarga',
  status: 'pending',
  employee: _employee,
  schedule: _publishedSchedule,
);
