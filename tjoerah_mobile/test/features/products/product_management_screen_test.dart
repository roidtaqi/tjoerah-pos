import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';
import 'package:tjoerah_mobile/features/pos/models/category_model.dart';
import 'package:tjoerah_mobile/features/pos/models/product_model.dart';
import 'package:tjoerah_mobile/features/products/providers/product_management_provider.dart';
import 'package:tjoerah_mobile/features/products/screens/product_management_screen.dart';

void main() {
  testWidgets('owner can browse product management on a compact phone', (
    tester,
  ) async {
    await _render(tester, role: 'owner');

    expect(find.text('Kelola produk'), findsOneWidget);
    expect(find.text('Kopi Susu Tjoerah'), findsOneWidget);
    expect(find.text('Aktif 1'), findsOneWidget);
    expect(find.text('Nonaktif 1'), findsOneWidget);
    expect(find.text('Tambah produk'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Kopi Susu Tjoerah'));
    await tester.pumpAndSettle();
    expect(find.text('Edit produk'), findsOneWidget);
    expect(find.text('Simpan perubahan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cashier cannot open product management actions', (tester) async {
    await _render(tester, role: 'cashier');

    expect(find.text('Akses dibatasi'), findsOneWidget);
    expect(find.text('Tambah produk'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _render(WidgetTester tester, {required String role}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _ProductAuthNotifier(role)),
        productManagementProvider.overrideWith(
          _PreviewProductManagementNotifier.new,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProductManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ProductAuthNotifier extends AuthNotifier {
  _ProductAuthNotifier(this.role);

  final String role;

  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {'name': 'Test User', 'role': role},
  );
}

class _PreviewProductManagementNotifier extends ProductManagementNotifier {
  @override
  Future<ProductManagementState> build() async {
    return const ProductManagementState(
      categories: [CategoryModel(id: '1', name: 'Kopi')],
      products: [
        ProductModel(
          id: '1',
          name: 'Kopi Susu Tjoerah',
          price: 28000,
          categoryId: '1',
          sku: 'KST-001',
          station: 'bar',
        ),
        ProductModel(
          id: '2',
          name: 'Menu Musiman',
          price: 32000,
          categoryId: '1',
          isActive: false,
        ),
      ],
    );
  }
}
