import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/utils/app_date_formatter.dart';

void main() {
  const expectedTime = '07:05';
  final date = DateTime(2026, 8, 3, 7, 5);

  test('formats Indonesian dates without locale initialization', () {
    expect(AppDateFormatter.dayMonthTime(date), '3 Agu, $expectedTime');
    expect(AppDateFormatter.shortDateTime(date), '03 Agu, $expectedTime');
    expect(AppDateFormatter.shortDate(date), '03 Agu 2026');
    expect(AppDateFormatter.dayMonth(date), '03 Agu');
    expect(AppDateFormatter.longDate(date), '3 Agustus 2026');
    expect(AppDateFormatter.weekdayLongDate(date), 'Senin, 3 Agustus 2026');
    expect(AppDateFormatter.weekdayShortDate(date), 'Sen, 03 Agu 2026');
    expect(AppDateFormatter.longDateTime(date), '3 Agustus 2026, 07:05');
  });
}
