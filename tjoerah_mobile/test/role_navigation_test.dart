import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/router/role_navigation.dart';
import 'package:tjoerah_mobile/core/router/shell_layout.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';

void main() {
  test('roles resolve from direct and assigned role payloads', () {
    expect(appRoleForUser({'role': 'owner'}), AppRole.owner);
    expect(appRoleForUser({'role': 'area_manager'}), AppRole.areaManager);
    expect(appRoleForUser({'role': 'cashier'}), AppRole.cashier);
    expect(appRoleForUser({'role': 'barista'}), AppRole.production);
    expect(
      appRoleForUser({
        'roles': [
          {'slug': 'outlet-manager'},
        ],
      }),
      AppRole.outletManager,
    );
  });

  test('every role receives the correct home and destinations', () {
    expect(homePathForUser({'role': 'owner'}), '/dashboard');
    expect(homePathForUser({'role': 'area_manager'}), '/dashboard');
    expect(homePathForUser({'role': 'cashier'}), '/pos');
    expect(homePathForUser({'role': 'kitchen_staff'}), '/kds');

    expect(destinationsForRole(AppRole.cashier).map((item) => item.label), [
      'POS',
      'Pesanan',
      'Pelanggan',
      'Lainnya',
    ]);
    expect(destinationsForRole(AppRole.owner).map((item) => item.label), [
      'Dashboard',
      'Operasional',
      'Stok',
      'Analitik',
      'Lainnya',
    ]);
  });

  testWidgets('shell renders only the destinations allowed for each role', (
    tester,
  ) async {
    await _renderShell(tester, role: 'owner', location: '/dashboard');
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Analitik'), findsOneWidget);
    expect(find.text('POS'), findsNothing);
    expect(tester.takeException(), isNull);

    await _renderShell(tester, role: 'cashier', location: '/pos');
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Pesanan'), findsOneWidget);
    expect(find.text('Pelanggan'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(tester.takeException(), isNull);

    await _renderShell(tester, role: 'barista', location: '/kds');
    expect(find.text('Dapur'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);
    expect(find.text('Stok'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _renderShell(
  WidgetTester tester, {
  required String role,
  required String location,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(() => _RoleAuthNotifier(role))],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: ShellLayout(
          currentLocation: location,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _RoleAuthNotifier extends AuthNotifier {
  _RoleAuthNotifier(this.role);

  final String role;

  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {'name': 'Test User', 'role': role},
  );
}
