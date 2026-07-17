import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/printer/print_job.dart';
import 'package:tjoerah_mobile/features/pos/screens/payment_screen.dart';
import 'package:tjoerah_mobile/features/settings/providers/printer_provider.dart';

void main() {
  testWidgets('payment success print controls fit a compact phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printerProvider.overrideWith(_UnavailablePrinterNotifier.new),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showPaymentSuccessDialog(context, _order),
                  child: const Text('Selesai'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Selesai'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran tersimpan'), findsOneWidget);
    expect(find.text('Cetak struk & dapur'), findsOneWidget);
    expect(find.text('Struk'), findsOneWidget);
    expect(find.text('Dapur'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _UnavailablePrinterNotifier extends PrinterNotifier {
  @override
  PrinterState build() => const PrinterState(
    error: 'Hubungkan printer dari Pengaturan untuk mencetak.',
  );
}

final _order = TransactionPrintData(
  orderId: '12345678-abcd-efgh',
  receiptNumber: 'TJ-260717-001',
  createdAt: DateTime(2026, 7, 17, 12),
  orderTypeLabel: 'Makan di tempat',
  paymentMethod: 'cash',
  paymentBreakdown: const {'cash': 44400},
  items: const [
    PrintOrderItem(
      name: 'Nasi Goreng',
      quantity: 1,
      unitPrice: 40000,
      station: 'kitchen',
    ),
  ],
  subtotal: 40000,
  discount: 0,
  tax: 4400,
  total: 44400,
  isSynced: true,
);
