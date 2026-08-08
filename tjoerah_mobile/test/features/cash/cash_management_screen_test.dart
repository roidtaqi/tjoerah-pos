import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/cash/models/cash_model.dart';
import 'package:tjoerah_mobile/features/cash/providers/cash_provider.dart';
import 'package:tjoerah_mobile/features/cash/screens/cash_management_screen.dart';

void main() {
  testWidgets('manager only monitors an active shared cash session', (
    tester,
  ) async {
    await _render(tester, _ManagerCashNotifier.new);

    expect(find.text('Pantauan manager'), findsOneWidget);
    expect(find.text('Tutup darurat'), findsOneWidget);
    expect(
      find.text('Mode pantau: transaksi kas hanya dapat dicatat oleh kasir.'),
      findsOneWidget,
    );
    expect(find.text('Uang masuk'), findsNothing);
    expect(find.text('Tutup kas'), findsNothing);
  });

  testWidgets('second cashier joins the same session without close access', (
    tester,
  ) async {
    await _render(tester, _JoinedCashierNotifier.new);

    expect(find.text('Sesi bersama'), findsOneWidget);
    expect(find.text('Uang masuk'), findsOneWidget);
    expect(find.text('Uang keluar'), findsOneWidget);
    expect(find.text('Tutup kas'), findsNothing);
    expect(find.text('Tutup darurat'), findsNothing);
  });
}

Future<void> _render(
  WidgetTester tester,
  CashNotifier Function() create,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1280);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [cashProvider.overrideWith(create)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CashManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ManagerCashNotifier extends CashNotifier {
  @override
  Future<CashOverview> build() async => _overview(
    canRecordMovement: false,
    canEmergencyClose: true,
    monitorOnly: true,
  );
}

class _JoinedCashierNotifier extends CashNotifier {
  @override
  Future<CashOverview> build() async =>
      _overview(canRecordMovement: true, joinedSharedShift: true);
}

CashOverview _overview({
  required bool canRecordMovement,
  bool canEmergencyClose = false,
  bool monitorOnly = false,
  bool joinedSharedShift = false,
}) {
  return CashOverview(
    outletId: 1,
    outletName: 'Tjoerah Renon',
    canOpen: false,
    canRecordMovement: canRecordMovement,
    canClose: false,
    canEmergencyClose: canEmergencyClose,
    monitorOnly: monitorOnly,
    joinedSharedShift: joinedSharedShift,
    currentShift: CashShift(
      id: 4,
      outletId: 1,
      number: 'KAS-004',
      status: 'open',
      startedAt: DateTime(2026, 8, 8, 7, 30),
      openedBy: 'Ayu Kasir',
      summary: const CashSummary(
        openingCash: 200000,
        cashSales: 50000,
        manualCashIn: 0,
        cashRefunds: 0,
        manualCashOut: 0,
        adjustmentsIn: 0,
        adjustmentsOut: 0,
        cashFundBalance: 200000,
        cashOnHand: 250000,
        expectedCash: 250000,
      ),
      movements: const [],
    ),
    recentShifts: const [],
  );
}
