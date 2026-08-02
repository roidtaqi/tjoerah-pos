import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/settings/models/transaction_settings.dart';

void main() {
  test('keeps the cached KDS mode when an older server omits it', () {
    final settings = TransactionSettings.fromJson({
      'outlet_id': 7,
      'tax_enabled': true,
      'tax_rate': 11,
    }, kdsModeFallback: 'automatic');

    expect(settings.outletId, 7);
    expect(settings.kdsMode, 'automatic');
    expect(settings.manualKds, isFalse);
  });

  test('uses a valid KDS mode returned by the server', () {
    final settings = TransactionSettings.fromJson({
      'outlet_id': 7,
      'tax_enabled': false,
      'tax_rate': 0,
      'kds_mode': 'manual',
    });

    expect(settings.kdsMode, 'manual');
    expect(settings.manualKds, isTrue);
  });
}
