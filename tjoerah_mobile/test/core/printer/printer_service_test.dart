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
}
