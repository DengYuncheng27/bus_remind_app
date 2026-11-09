DateTime chinaToday([DateTime? now]) {
  final value = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime.utc(value.year, value.month, value.day);
}

String dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
List<int> daysFromMask(int mask) => [
  for (var day = 1; day <= 7; day++)
    if ((mask & (1 << (day - 1))) != 0) day,
];
int daysMask(Iterable<int> days) =>
    days.fold(0, (mask, day) => mask | (1 << (day - 1)));
String daysText(List<int> days) => days.length == 7
    ? '每天'
    : days.map((day) => '周${weekdayNames[day - 1]}').join('、');

class RepeatSchedule {
  final String mode;
  final int intervalWeeks;
  final List<int> weekdays;
  final DateTime anchor;
  final bool skipHolidays;
  RepeatSchedule({
    this.mode = 'custom',
    this.intervalWeeks = 1,
    this.weekdays = const [1, 2, 3, 4, 5],
    DateTime? anchor,
    this.skipHolidays = false,
  }) : anchor = anchor ?? chinaToday();

  factory RepeatSchedule.fromReminder(Map<String, dynamic> reminder) =>
      RepeatSchedule(
        mode: reminder['schedule_mode'] ?? 'custom',
        intervalWeeks: reminder['schedule_interval_weeks'] ?? 1,
        weekdays: daysFromMask(reminder['schedule_weekdays_mask'] ?? 31),
        anchor: DateTime.tryParse(
          '${reminder['schedule_anchor_date']}T00:00:00Z',
        ),
        skipHolidays:
            reminder['skip_statutory_holidays'] == 1 ||
            reminder['skip_statutory_holidays'] == true,
      );

  String get summary {
    if (mode == 'daily') return '每天';
    if (mode == 'china_workday') return '法定工作日';
    final repeat =
        '${intervalWeeks == 1 ? '每周' : '每 $intervalWeeks 周'} · ${daysText(weekdays)}';
    return '$repeat${skipHolidays ? ' · 跳过法定节假日' : ''}';
  }

  Map<String, dynamic> toJson() => mode != 'custom'
      ? {'mode': mode}
      : {
          'mode': 'custom',
          'intervalWeeks': intervalWeeks,
          'weekdays': [...weekdays]..sort(),
          'anchorDate': dateText(anchor),
          'skipStatutoryHolidays': skipHolidays,
        };
}
