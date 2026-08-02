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
    expect(appRoleForUser({'role': 'admin'}), AppRole.admin);
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
    expect(
      appRoleForUser({
        'role': 'cashier',
        'roles': [
          {'slug': 'admin'},
        ],
      }),
      AppRole.cashier,
    );
    expect(
      destinationsForUser({
        'role': 'cashier',
        'roles': [
          {'slug': 'cashier'},
          {'slug': 'barista'},
        ],
      }).map((item) => item.path),
      ['/pos', '/orders', '/customers', '/kds', '/settings'],
    );
    expect(
      canManageProductsForUser({
        'role': 'cashier',
        'roles': [
          {'slug': 'admin'},
        ],
      }),
      isTrue,
    );
  });

  test('every role receives the correct home and destinations', () {
    expect(homePathForUser({'role': 'owner'}), '/dashboard');
    expect(homePathForUser({'role': 'admin'}), '/dashboard');
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
    expect(canManageProductsForUser({'role': 'owner'}), isTrue);
    expect(canManageProductsForUser({'role': 'admin'}), isTrue);
    expect(canManageProductsForUser({'role': 'cashier'}), isFalse);
    expect(canManageAttendanceForUser({'role': 'owner'}), isTrue);
    expect(canManageAttendanceForUser({'role': 'cashier'}), isFalse);
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

  testWidgets('owner order history remains grouped under operations', (
    tester,
  ) async {
    await _renderShell(tester, role: 'owner', location: '/orders');

    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 1);
    expect(find.text('Operasional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every role shell fits the SM T220 landscape viewport', (
    tester,
  ) async {
    const roles = [
      ('owner', '/dashboard'),
      ('area_manager', '/dashboard'),
      ('outlet_manager', '/pos'),
      ('cashier', '/pos'),
      ('barista', '/kds'),
    ];

    for (final (role, location) in roles) {
      await _renderShell(
        tester,
        role: role,
        location: location,
        size: const Size(1007, 553),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$role navigation overflowed on the SM T220.',
      );
    }
  });

  testWidgets('cashier shell stays stable behind the landscape keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1007, 553);
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _RoleAuthNotifier('cashier')),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ShellLayout(
            currentLocation: '/customers',
            child: ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _renderShell(
  WidgetTester tester, {
  required String role,
  required String location,
  Size size = const Size(390, 844),
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
