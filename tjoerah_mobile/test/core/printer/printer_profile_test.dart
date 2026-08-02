import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/printer/printer_profile.dart';

void main() {
  test('production stations never fall back to another printer profile', () {
    expect(printerDestinationForStation('bar'), PrinterDestination.bar);
    expect(printerDestinationForStation('kitchen'), PrinterDestination.kitchen);
  });

  test('printer profile round-trips detailed settings', () {
    final profile = PrinterProfile.defaults(PrinterDestination.kitchen)
        .copyWith(
          deviceAddress: 'AA:BB:CC:DD',
          deviceName: 'Kitchen-01',
          paperWidth: PrinterPaperWidth.mm80,
          copies: 2,
          autoPrint: false,
          cutPaper: false,
        );

    final restored = PrinterProfile.fromJson(
      PrinterDestination.kitchen,
      profile.toJson(),
    );

    expect(restored.isConfigured, isTrue);
    expect(restored.deviceName, 'Kitchen-01');
    expect(restored.deviceAddress, 'AA:BB:CC:DD');
    expect(restored.paperWidth, PrinterPaperWidth.mm80);
    expect(restored.paperWidth.characters, 48);
    expect(restored.copies, 2);
    expect(restored.autoPrint, isFalse);
    expect(restored.cutPaper, isFalse);
  });

  test('printer MAC address is normalized for stable device matching', () {
    final profile = PrinterProfile.defaults(
      PrinterDestination.cashier,
    ).copyWith(deviceAddress: ' aa:bb:cc:dd ', deviceName: 'MTP-II');

    expect(profile.deviceAddress, 'AA:BB:CC:DD');
    expect(normalizePrinterAddress('aa:01:bb:02'), 'AA:01:BB:02');
  });

  test('copy count stays within the supported range', () {
    final profile = PrinterProfile.defaults(PrinterDestination.cashier);

    expect(profile.copyWith(copies: 0).copies, 1);
    expect(profile.copyWith(copies: 9).copies, 3);
  });
}
