import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/attendance/models/attendance_models.dart';

void main() {
  test('attendance timestamps without an offset are treated as UTC', () {
    final record = AttendanceRecord.fromJson({
      'id': 1,
      'employee_id': 2,
      'outlet_id': 3,
      'work_date': '2026-08-08',
      'scheduled_start_at': '2026-08-07T23:30:00',
      'check_in_at': '2026-08-08T00:15:00',
    });

    expect(record.scheduledStartAt?.isUtc, isTrue);
    expect(
      record.scheduledStartAt?.toIso8601String(),
      '2026-08-07T23:30:00.000Z',
    );
    expect(record.checkInAt?.toIso8601String(), '2026-08-08T00:15:00.000Z');
    expect(record.workDate?.year, 2026);
    expect(record.workDate?.month, 8);
    expect(record.workDate?.day, 8);
  });

  test('attendance timestamps with WITA offset preserve the same instant', () {
    final record = AttendanceRecord.fromJson({
      'id': 1,
      'employee_id': 2,
      'outlet_id': 3,
      'check_in_at': '2026-08-08T08:15:00+08:00',
    });

    expect(record.checkInAt?.isUtc, isTrue);
    expect(record.checkInAt?.toIso8601String(), '2026-08-08T00:15:00.000Z');
  });
}
