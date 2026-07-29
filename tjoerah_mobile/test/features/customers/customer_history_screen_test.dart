import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/customers/models/customer_model.dart';
import 'package:tjoerah_mobile/features/customers/providers/customer_provider.dart';
import 'package:tjoerah_mobile/features/customers/screens/customers_screen.dart';
import 'package:tjoerah_mobile/features/orders/models/order_history_model.dart';
import 'package:tjoerah_mobile/features/orders/providers/order_history_provider.dart';

void main() {
  testWidgets(
    'customer detail shows linked transaction history in Indonesian',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1007, 553);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerProvider.overrideWith(_CustomerNotifier.new),
            customerOrderHistoryProvider.overrideWith((ref, customerId) async {
              expect(customerId, '42');
              return [
                OrderHistoryItem(
                  id: 'order-1',
                  receiptNumber: 'TJ-260729-001',
                  orderType: 'take_away',
                  paymentMethod: 'cash',
                  total: 38850,
                  createdAt: DateTime(2026, 7, 29, 11, 21),
                  syncStatus: 'synced',
                  customerId: customerId,
                  customerName: 'Ayu',
                  items: const [
                    OrderHistoryLine(
                      name: 'Kopi Tjoerah',
                      quantity: 1,
                      price: 35000,
                      total: 35000,
                    ),
                  ],
                  paymentBreakdown: const {'cash': 38850},
                ),
              ];
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CustomersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ayu').last);
      await tester.pumpAndSettle();

      expect(find.text('Riwayat transaksi'), findsOneWidget);
      expect(find.text('TJ-260729-001'), findsOneWidget);
      expect(find.text('29 Juli 2026, 11:21 · 1 item'), findsOneWidget);
      expect(find.text('Rp 38.850'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('TJ-260729-001'));
      await tester.pumpAndSettle();

      expect(find.text('1x Kopi Tjoerah'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CustomerNotifier extends CustomerNotifier {
  @override
  Future<List<CustomerModel>> build() async => const [
    CustomerModel(
      id: '42',
      name: 'Ayu',
      phone: '081234567890',
      email: 'ayu@example.com',
      totalSpent: 0,
      visitCount: 0,
      isSynced: true,
    ),
  ];
}
