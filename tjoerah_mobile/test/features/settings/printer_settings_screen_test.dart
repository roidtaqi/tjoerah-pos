import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/printer/printer_device.dart';
import 'package:tjoerah_mobile/core/printer/printer_profile.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/features/settings/providers/printer_provider.dart';
import 'package:tjoerah_mobile/features/settings/screens/printer_settings_screen.dart';

void main() {
  testWidgets(
    'printer picker distinguishes duplicate names with device identifiers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            printerProvider.overrideWith(_PrinterSettingsTestNotifier.new),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PrinterSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MTP-II'), findsOneWidget);
      expect(find.text('ID AA:BB:CC:01'), findsOneWidget);

      await tester.tap(find.text('MTP-II'));
      await tester.pumpAndSettle();

      expect(find.text('Pilih printer kasir'), findsOneWidget);
      expect(find.text('MTP-II'), findsNWidgets(3));
      expect(find.text('ID AA:BB:CC:01'), findsWidgets);
      expect(find.text('ID AA:BB:CC:02'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PrinterSettingsTestNotifier extends PrinterNotifier {
  @override
  PrinterState build() => PrinterState(
    devices: [
      const PrinterDevice(name: 'MTP-II', identifier: 'AA:BB:CC:01'),
      const PrinterDevice(name: 'MTP-II', identifier: 'AA:BB:CC:02'),
    ],
    profiles: {
      PrinterDestination.cashier: PrinterProfile.defaults(
        PrinterDestination.cashier,
      ).copyWith(deviceName: 'MTP-II', deviceAddress: 'AA:BB:CC:01'),
      PrinterDestination.kitchen: PrinterProfile.defaults(
        PrinterDestination.kitchen,
      ),
      PrinterDestination.bar: PrinterProfile.defaults(PrinterDestination.bar),
    },
    isInitialized: true,
  );
}
