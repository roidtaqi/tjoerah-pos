import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';
import 'package:tjoerah_mobile/features/auth/screens/login_screen.dart';
import 'package:tjoerah_mobile/features/pos/screens/order_type_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login remains usable on a compact phone', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Tjoerah POS'), findsOneWidget);
    expect(find.text('Masuk untuk melanjutkan pekerjaan'), findsOneWidget);
    expect(find.text('Masuk ke Tjoerah POS'), findsOneWidget);

    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masuk dengan PIN'));
    await tester.pump();

    expect(find.text('PIN minimal 4 digit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order type choices adapt to tablet width', (tester) async {
    await _setViewport(tester, const Size(1024, 768));
    await tester.pumpWidget(_testApp(const OrderTypeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Pilih tipe pesanan'), findsOneWidget);
    expect(find.text('Makan di tempat'), findsOneWidget);
    expect(find.text('Bawa pulang'), findsOneWidget);
    expect(find.text('Pesan antar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login distinguishes a server failure from wrong credentials', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(const LoginScreen(), simulateUnavailableAuth: true),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('email-field')),
      'owner@tjoerah.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.text('Masuk ke Tjoerah POS'));
    await tester.pumpAndSettle();

    expect(
      find.text('Layanan sedang bermasalah. Tunggu sebentar lalu coba lagi.'),
      findsOneWidget,
    );
    expect(find.textContaining('kata sandi tidak sesuai'), findsNothing);
  });
}

Widget _testApp(Widget child, {bool simulateUnavailableAuth = false}) {
  return ProviderScope(
    overrides: [
      if (simulateUnavailableAuth)
        authProvider.overrideWith(_UnavailableAuthNotifier.new),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: child,
    ),
  );
}

class _UnavailableAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState();

  @override
  Future<AuthLoginResult> login(
    String loginId,
    String password, {
    bool isPin = false,
  }) async {
    return const AuthLoginResult.failure(AuthLoginFailure.serviceUnavailable);
  }
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
