import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';
import 'package:tjoerah_mobile/features/pos/models/category_model.dart';
import 'package:tjoerah_mobile/features/pos/models/product_model.dart';
import 'package:tjoerah_mobile/features/products/providers/product_management_provider.dart';
import 'package:tjoerah_mobile/features/products/screens/category_management_screen.dart';

void main() {
  testWidgets('owner can browse category management on a compact phone', (
    tester,
  ) async {
    await _render(tester, role: 'owner');

    expect(find.text('Kelola kategori'), findsOneWidget);
    expect(find.text('Minuman'), findsOneWidget);
    expect(find.text('Kopi'), findsOneWidget);
    expect(find.text('2 kategori'), findsOneWidget);
    expect(find.text('Tambah kategori'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Kopi'));
    await tester.pumpAndSettle();
    expect(find.text('Edit kategori'), findsOneWidget);
    expect(find.text('Simpan perubahan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cashier cannot open category management actions', (
    tester,
  ) async {
    await _render(tester, role: 'cashier');

    expect(find.text('Akses dibatasi'), findsOneWidget);
    expect(find.text('Tambah kategori'), findsNothing);
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
        authProvider.overrideWith(() => _CategoryAuthNotifier(role)),
        productManagementProvider.overrideWith(
          _PreviewCategoryManagementNotifier.new,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CategoryManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _CategoryAuthNotifier extends AuthNotifier {
  _CategoryAuthNotifier(this.role);

  final String role;

  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {'name': 'Test User', 'role': role},
  );
}

class _PreviewCategoryManagementNotifier extends ProductManagementNotifier {
  @override
  Future<ProductManagementState> build() async {
    return const ProductManagementState(
      categories: [
        CategoryModel(id: '1', name: 'Minuman'),
        CategoryModel(id: '2', name: 'Kopi', parentId: '1', sortOrder: 1),
      ],
      products: [
        ProductModel(
          id: '1',
          name: 'Kopi Susu Tjoerah',
          price: 28000,
          categoryId: '2',
        ),
      ],
    );
  }
}
