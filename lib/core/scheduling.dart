import 'package:timezone/timezone.dart' as tz;
import '../models/commitment.dart';

({DateTime start, DateTime end}) resolveWindow(
  CommitmentSchedule s,
  DateTime day,
) {
  final zone = tz.getLocation(s.timezone);
  DateTime at(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return tz.TZDateTime(
      zone,
      day.year,
      day.month,
      day.day,
      parts[0],
      parts[1],
    ).toUtc();
  }

  return (start: at(s.windowStartLocal), end: at(s.windowEndLocal));
}

DateTime nextWindow(CommitmentSchedule s, DateTime now) {
  final local = tz.TZDateTime.from(now, tz.getLocation(s.timezone));
  for (var i = 0; i < 8; i++) {
    final day = DateTime(local.year, local.month, local.day + i);
    final w = resolveWindow(s, day);
    if (s.daysOfWeek.contains(day.weekday) && w.end.isAfter(now)) {
      return w.start;
    }
  }
  throw StateError('No scheduled day');
}

List<DateTime> reminderTimes(
  DateTime start,
  DateTime end,
  ReminderConfig r, {
  bool terminal = false,
}) => terminal
    ? []
    : [
        for (var i = 0; i < r.maxReminders; i++)
          if (start.add(Duration(minutes: i * r.intervalMinutes)).isBefore(end))
            start.add(Duration(minutes: i * r.intervalMinutes)),
      ];
