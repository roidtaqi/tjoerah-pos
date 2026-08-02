import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';
import 'package:tjoerah_mobile/features/employees/models/employee_models.dart';
import 'package:tjoerah_mobile/features/employees/providers/employee_provider.dart';
import 'package:tjoerah_mobile/features/employees/screens/employee_management_screen.dart';

void main() {
  testWidgets('owner can browse and open the employee form', (tester) async {
    await _render(tester, role: 'owner', size: const Size(390, 2400));

    expect(find.text('Karyawan & akses'), findsOneWidget);
    expect(find.text('Ayu Lestari'), findsOneWidget);
    expect(find.text('Kasir'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Karyawan baru'), findsOneWidget);
    expect(find.text('Data kerja'), findsOneWidget);
    expect(find.text('Akses aplikasi'), findsOneWidget);
    expect(find.text('Nomor karyawan *'), findsOneWidget);
    expect(find.text('Jabatan (opsional)'), findsOneWidget);
    expect(find.text('Username login (opsional)'), findsOneWidget);
    expect(find.text('Shift absensi'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Tambahkan karyawan'));
    await tester.tap(find.text('Tambahkan karyawan'));
    await tester.pumpAndSettle();

    expect(find.text('Karyawan baru'), findsOneWidget);
    expect(find.text('Lengkapi data wajib'), findsOneWidget);
    expect(find.textContaining('Nomor karyawan'), findsWidgets);
    expect(find.text('Kolom ini wajib diisi.'), findsWidgets);
    expect(find.text('Lengkapi kolom wajib yang ditandai *.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee management fits the SM T220 landscape viewport', (
    tester,
  ) async {
    await _render(tester, role: 'owner', size: const Size(1007, 553));

    expect(find.text('Ayu Lestari'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tambah karyawan'));
    await tester.pumpAndSettle();
    expect(find.text('Karyawan baru'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cashier cannot manage employees', (tester) async {
    await _render(tester, role: 'cashier');

    expect(find.text('Akses dibatasi'), findsOneWidget);
    expect(find.text('Ayu Lestari'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _render(
  WidgetTester tester, {
  required String role,
  Size size = const Size(390, 844),
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _EmployeeAuthNotifier(role)),
        employeeProvider.overrideWith(_PreviewEmployeeNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const EmployeeManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _EmployeeAuthNotifier extends AuthNotifier {
  _EmployeeAuthNotifier(this.role);

  final String role;

  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {'name': 'Test User', 'role': role},
  );
}

class _PreviewEmployeeNotifier extends EmployeeNotifier {
  @override
  Future<EmployeeManagementState> build() async {
    return const EmployeeManagementState(
      employees: [
        EmployeeProfile(
          id: 1,
          employeeNumber: 'EMP-001',
          name: 'Ayu Lestari',
          email: 'ayu@tjoerah.test',
          role: 'cashier',
          outletId: 1,
          outletName: 'Renon',
          attendanceShiftId: 1,
          shiftName: 'Shift Pagi',
          position: 'Kasir',
          isActive: true,
        ),
      ],
      roles: [
        EmployeeRoleOption(
          value: 'admin',
          label: 'Admin',
          description: 'Mengelola operasional.',
        ),
        EmployeeRoleOption(
          value: 'cashier',
          label: 'Kasir',
          description: 'Menjalankan transaksi POS.',
        ),
        EmployeeRoleOption(
          value: 'barista',
          label: 'Barista',
          description: 'Menjalankan produksi minuman.',
        ),
      ],
      outlets: [
        EmployeeOutletOption(
          id: 1,
          name: 'Renon',
          shifts: [
            EmployeeShiftOption(
              id: 1,
              name: 'Shift Pagi',
              startTime: '07:30',
              lateAfterTime: '07:45',
              endTime: '15:30',
            ),
            EmployeeShiftOption(
              id: 2,
              name: 'Shift Kedua',
              startTime: '15:30',
              lateAfterTime: '15:45',
              endTime: '23:30',
            ),
          ],
        ),
      ],
      employmentStatuses: [
        EmploymentStatusOption(value: 'permanent', label: 'Tetap'),
        EmploymentStatusOption(value: 'contract', label: 'Kontrak'),
      ],
    );
  }
}
