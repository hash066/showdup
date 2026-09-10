import 'dart:math' as math;
import 'package:timezone/timezone.dart' as tz;
import '../models/commitment.dart';

/// Only [day]'s year, month and day are read; the schedule's timezone
/// decides the instants.
({DateTime start, DateTime end}) resolveWindow(
  CommitmentSchedule s,
  DateTime day,
) {
  final zone = tz.getLocation(s.timezone);
  DateTime at(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return _wallToUtc(zone, day.year, day.month, day.day, parts[0], parts[1]);
  }

  return (start: at(s.windowStartLocal), end: at(s.windowEndLocal));
}

/// Converts a wall-clock time in [zone] to an instant the way java.time does
/// for native reminders and luxon does for server windows: a time skipped by
/// a DST gap moves forward by the gap, and a repeated time resolves to its
/// earlier occurrence. The timezone package alone picks the later
/// occurrence in zones east of UTC.
DateTime _wallToUtc(tz.Location zone, int y, int mo, int d, int h, int mi) {
  final wall = DateTime.utc(y, mo, d, h, mi).millisecondsSinceEpoch;
  int offsetAt(int ms) => tz.TZDateTime.fromMillisecondsSinceEpoch(
    zone,
    ms,
  ).timeZoneOffset.inMilliseconds;
  const dayMs = 86400000;
  final offsets = {
    offsetAt(wall - dayMs),
    offsetAt(wall),
    offsetAt(wall + dayMs),
  };
  int? earliest;
  for (final o in offsets) {
    final utc = wall - o;
    if (offsetAt(utc) == o && (earliest == null || utc < earliest)) {
      earliest = utc;
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(
    earliest ?? wall - offsets.reduce(math.min),
    isUtc: true,
  );
}

DateTime nextWindow(CommitmentSchedule s, DateTime now) {
  final local = tz.TZDateTime.from(now, tz.getLocation(s.timezone));
  for (var i = 0; i < 8; i++) {
    // A UTC date carrier: device-local midnight can fall in a DST gap.
    final day = DateTime.utc(local.year, local.month, local.day + i);
    final w = resolveWindow(s, day);
    if (s.daysOfWeek.contains(day.weekday) && w.start.isAfter(now)) {
      return w.start;
    }
  }
  throw StateError('No scheduled day');
}

DateTime inScheduleTimezone(CommitmentSchedule s, DateTime instant) =>
    tz.TZDateTime.from(instant, tz.getLocation(s.timezone));

/// Mirrors the server's recordReminderEvent bounds: index < maxReminders and
/// start + index * interval strictly before the window end.
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
