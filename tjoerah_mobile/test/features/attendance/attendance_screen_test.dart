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
    expect(find.text('Jadwal'), findsOneWidget);
    expect(find.text('Kebijakan'), findsOneWidget);
    expect(find.text('Hadir'), findsOneWidget);
    expect(find.text('Rani Kasir'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Jadwal'));
    await tester.pumpAndSettle();
    expect(find.text('Jadwal karyawan'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Kebijakan'));
    await tester.pumpAndSettle();
    expect(find.text('Jam kerja'), findsOneWidget);
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
}

Future<void> _render(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
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
);

const _outlet = AttendanceOutlet(id: 1, name: 'Tjoerah Utama');

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
  scheduledEndAt: DateTime.utc(2026, 7, 24, 9),
  checkInAt: DateTime.utc(2026, 7, 24, 0, 20),
  punctualityStatus: 'late',
  lateMinutes: 10,
  employee: _employee,
  outlet: _outlet,
);

final _context = AttendanceContextModel(
  employee: _employee,
  outlet: _outlet,
  policy: _policy,
  scheduledStartAt: DateTime.utc(2026, 7, 24),
  scheduledEndAt: DateTime.utc(2026, 7, 24, 9),
  serverTime: DateTime.utc(2026, 7, 24),
  recentAttendance: [_record],
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
  schedules: const [],
  dateFrom: DateTime(2026, 7, 1),
  dateTo: DateTime(2026, 7, 31),
);
