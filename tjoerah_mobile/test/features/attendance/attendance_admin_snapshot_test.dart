import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/features/attendance/repositories/attendance_repository.dart';

void main() {
  test('parses the combined attendance administration payload', () {
    final snapshot = AttendanceAdminSnapshot.fromJson({
      'outlets': [
        {'id': 7, 'name': 'Tjoerah Renon', 'timezone': 'Asia/Makassar'},
      ],
      'selected_outlet': {
        'id': 7,
        'name': 'Tjoerah Renon',
        'timezone': 'Asia/Makassar',
      },
      'policy': {'outlet_id': 7, 'late_tolerance_minutes': 15},
      'employees': [
        {'id': 12, 'name': 'Ayu', 'outlet_id': 7},
      ],
      'summary': {
        'total': 1,
        'on_time': 0,
        'late': 1,
        'pending_review': 1,
        'early_leave': 0,
        'late_minutes': 8,
      },
      'records': {
        'data': [
          {
            'id': 31,
            'employee_id': 12,
            'outlet_id': 7,
            'punctuality_status': 'late',
            'late_minutes': 8,
            'employee': {'id': 12, 'name': 'Ayu', 'outlet_id': 7},
          },
        ],
      },
      'schedules': <Map<String, dynamic>>[],
      'shifts': [
        {
          'id': 4,
          'outlet_id': 7,
          'name': 'Shift Pagi',
          'start_time': '07:30',
          'late_after_time': '07:45',
          'end_time': '15:30',
        },
      ],
    });

    expect(snapshot.selectedOutlet.name, 'Tjoerah Renon');
    expect(snapshot.employees.single.name, 'Ayu');
    expect(snapshot.summary.late, 1);
    expect(snapshot.records.single.lateMinutes, 8);
    expect(snapshot.shifts.single.lateAfterTime, '07:45');
  });
}
