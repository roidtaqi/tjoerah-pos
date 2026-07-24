abstract final class AppDateFormatter {
  static const _shortMonths = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static const _longMonths = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const _weekdays = <String>[
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static const _shortWeekdays = <String>[
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
    'Min',
  ];

  static String dayMonthTime(DateTime value) =>
      '${value.day} ${_shortMonth(value)}, ${_time(value)}';

  static String shortDateTime(DateTime value) =>
      '${_twoDigits(value.day)} ${_shortMonth(value)}, ${_time(value)}';

  static String shortDate(DateTime value) =>
      '${_twoDigits(value.day)} ${_shortMonth(value)} ${value.year}';

  static String dayMonth(DateTime value) =>
      '${_twoDigits(value.day)} ${_shortMonth(value)}';

  static String longDate(DateTime value) =>
      '${value.day} ${_longMonths[value.month - 1]} ${value.year}';

  static String weekdayLongDate(DateTime value) =>
      '${_weekdays[value.weekday - 1]}, ${longDate(value)}';

  static String weekdayShortDate(DateTime value) =>
      '${_shortWeekdays[value.weekday - 1]}, ${shortDate(value)}';

  static String longDateTime(DateTime value) =>
      '${longDate(value)}, ${_time(value)}';

  static String _shortMonth(DateTime value) => _shortMonths[value.month - 1];

  static String _time(DateTime value) =>
      '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
