import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/printer/printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.tjoerah.tjoerah_mobile/system');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Bluetooth settings are opened through the app activity channel',
    () async {
      String? invokedMethod;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invokedMethod = call.method;
            return true;
          });

      await PrinterService.instance.openBluetoothSettings();

      expect(invokedMethod, 'openBluetoothSettings');
    },
  );

  test('connection is reused only for the same printer identifier', () {
    expect(
      canReusePrinterConnection(
        nativeConnected: true,
        connectedAddress: 'AA:BB:CC:DD:EE:01',
        targetAddress: 'aa:bb:cc:dd:ee:01',
      ),
      isTrue,
    );
    expect(
      canReusePrinterConnection(
        nativeConnected: true,
        connectedAddress: 'AA:BB:CC:DD:EE:01',
        targetAddress: 'AA:BB:CC:DD:EE:02',
      ),
      isFalse,
    );
  });

  test('unknown native connection is never reused', () {
    expect(
      canReusePrinterConnection(
        nativeConnected: true,
        connectedAddress: null,
        targetAddress: 'AA:BB:CC:DD:EE:02',
      ),
      isFalse,
    );
  });

  test('Bluetooth printing is supported on Android and iOS', () {
    expect(isPrinterPlatformSupported(TargetPlatform.android), isTrue);
    expect(isPrinterPlatformSupported(TargetPlatform.iOS), isTrue);
    expect(isPrinterPlatformSupported(TargetPlatform.linux), isFalse);
    expect(isPrinterPlatformSupported(TargetPlatform.windows), isFalse);
  });
}
