import 'enums.dart';
import 'verifier_config.dart';
import 'package:timezone/timezone.dart' as tz;

class DailyWindow {
  const DailyWindow({required this.startLocal, required this.endLocal});

  final String startLocal;
  final String endLocal;

  Map<String, dynamic> toJson() => {
    'startLocal': startLocal,
    'endLocal': endLocal,
  };

  factory DailyWindow.fromJson(Map<String, dynamic> json) => DailyWindow(
    startLocal: json['startLocal'] as String,
    endLocal: json['endLocal'] as String,
  );
}

class CommitmentSchedule {
  const CommitmentSchedule({
    required this.daysOfWeek,
    required this.windowStartLocal,
    required this.windowEndLocal,
    required this.timezone,
    this.dayWindows = const {},
  });

  /// ISO weekdays, 1 = Monday .. 7 = Sunday.
  final List<int> daysOfWeek;
  final String windowStartLocal; // "06:30"
  final String windowEndLocal; // "09:00"
  final String timezone; // IANA, e.g. "Asia/Kolkata"
  /// Optional Pro overrides keyed by ISO weekday. Missing days use the
  /// default window, which keeps existing saved schedules compatible.
  final Map<int, DailyWindow> dayWindows;

  bool get hasCustomWindows => dayWindows.isNotEmpty;
  String startFor(int weekday) =>
      dayWindows[weekday]?.startLocal ?? windowStartLocal;
  String endFor(int weekday) => dayWindows[weekday]?.endLocal ?? windowEndLocal;

  String? validate() {
    if (daysOfWeek.isEmpty) return 'Pick at least one day.';
    if (daysOfWeek.any((d) => d < 1 || d > 7)) return 'Invalid weekday.';
    final baseError = _validateWindow(windowStartLocal, windowEndLocal);
    if (baseError != null) return baseError;
    if (dayWindows.keys.any((day) => !daysOfWeek.contains(day))) {
      return 'Custom times may only be set for selected days.';
    }
    for (final day in daysOfWeek) {
      final custom = dayWindows[day];
      if (custom == null) continue;
      final error = _validateWindow(custom.startLocal, custom.endLocal);
      if (error != null) return 'Day $day: $error';
    }
    try {
      tz.getLocation(timezone);
    } catch (_) {
      return 'Use a valid IANA timezone, such as Asia/Kolkata.';
    }
    return null;
  }

  static int? _mins(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || m < 0 || h > 23 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }

  static String? _validateWindow(String start, String end) {
    final s = _mins(start), e = _mins(end);
    if (s == null || e == null) return 'Times must be HH:mm.';
    if (e <= s) return 'Window must end after it starts.';
    if (e - s < 15) return 'Window must be at least 15 minutes.';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'daysOfWeek': daysOfWeek,
    'windowStartLocal': windowStartLocal,
    'windowEndLocal': windowEndLocal,
    'timezone': timezone,
    if (dayWindows.isNotEmpty)
      'dayWindows': {
        for (final entry in dayWindows.entries)
          entry.key.toString(): entry.value.toJson(),
      },
  };

  factory CommitmentSchedule.fromJson(Map<String, dynamic> j) {
    final rawWindows = Map<String, dynamic>.from(
      j['dayWindows'] as Map? ?? const {},
    );
    final parsedWindows = <int, DailyWindow>{};
    for (final entry in rawWindows.entries) {
      final day = int.tryParse(entry.key);
      if (day != null) {
        parsedWindows[day] = DailyWindow.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    return CommitmentSchedule(
      daysOfWeek: (j['daysOfWeek'] as List).map((e) => e as int).toList(),
      windowStartLocal: j['windowStartLocal'] as String,
      windowEndLocal: j['windowEndLocal'] as String,
      timezone: j['timezone'] as String,
      dayWindows: parsedWindows,
    );
  }
}

class ReminderConfig {
  const ReminderConfig({
    this.intervalMinutes = 20,
    this.volumeMode = VolumeMode.gentle,
    this.maxReminders = 6,
  });

  final int intervalMinutes;
  final VolumeMode volumeMode;
  final int maxReminders;

  String? validate() {
    if (intervalMinutes < 5 || intervalMinutes > 120) {
      return 'Interval must be between 5 and 120 minutes.';
    }
    if (maxReminders < 1 || maxReminders > 6) {
      return 'Reminder pulses must be between 1 and 6.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'intervalMinutes': intervalMinutes,
    'volumeMode': volumeMode.wire,
    'maxReminders': maxReminders,
  };

  factory ReminderConfig.fromJson(Map<String, dynamic> j) => ReminderConfig(
    intervalMinutes: (j['intervalMinutes'] as num).toInt(),
    volumeMode: VolumeMode.from(j['volumeMode'] as String),
    maxReminders: (j['maxReminders'] as num).toInt(),
  );
}

class Restrictions {
  const Restrictions({this.enabled = false, this.packages = const []});
  final bool enabled;
  final List<String> packages;

  /// Never blockable, whatever the user picks.
  static const neverBlock = <String>[
    'com.android.dialer',
    'com.google.android.dialer',
    'com.android.server.telecom',
    'com.google.android.apps.maps',
    selfPackage,
  ];
  static const selfPackage = 'com.rayyanshaikh.orbit';

  Map<String, dynamic> toJson() => {'enabled': enabled, 'packages': packages};

  factory Restrictions.fromJson(Map<String, dynamic> j) => Restrictions(
    enabled: j['enabled'] as bool? ?? false,
    packages: (j['packages'] as List? ?? []).map((e) => e as String).toList(),
  );
}

class GuardrailProfile {
  const GuardrailProfile({this.packages = const []});
  final List<String> packages;

  Map<String, dynamic> toJson() => {'packages': packages};
  factory GuardrailProfile.fromJson(Map<String, dynamic> json) =>
      GuardrailProfile(
        packages: (json['packages'] as List? ?? const []).cast<String>(),
      );
}

class Commitment {
  const Commitment({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.verifierType,
    required this.verifierConfig,
    required this.schedule,
    required this.reminder,
    required this.restrictions,
    required this.status,
    this.kind = CommitmentKind.walk,
    this.reason,
  });

  final String id;
  final String ownerUid;
  final String title;
  final VerifierType verifierType;
  final VerifierConfig verifierConfig;
  final CommitmentSchedule schedule;
  final ReminderConfig reminder;
  final Restrictions restrictions;
  final CommitmentStatus status;
  final CommitmentKind kind;

  /// "Why does this matter?" in the person's own words. Stays on the phone.
  final String? reason;

  String? validate() =>
      verifierConfig.validate() ??
      schedule.validate() ??
      reminder.validate() ??
      (title.trim().isEmpty ? 'Give it a name.' : null) ??
      ((reason?.length ?? 0) > 120
          ? 'Keep your reason under 120 characters.'
          : null);

  Map<String, dynamic> toJson() => {
    'ownerUid': ownerUid,
    'title': title,
    'verifierType': verifierType.wire,
    'verifierConfig': verifierConfig.toJson(),
    'schedule': schedule.toJson(),
    'reminder': reminder.toJson(),
    'restrictions': restrictions.toJson(),
    'status': status.wire,
    'kind': kind.wire,
    if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
  };

  factory Commitment.fromJson(String id, Map<String, dynamic> j) {
    final verifier = VerifierType.from(j['verifierType'] as String);
    return Commitment(
      id: id,
      ownerUid: j['ownerUid'] as String,
      title: j['title'] as String,
      verifierType: verifier,
      verifierConfig: VerifierConfig.fromJson(
        j['verifierType'] as String,
        Map<String, dynamic>.from(j['verifierConfig'] as Map),
      ),
      schedule: CommitmentSchedule.fromJson(
        Map<String, dynamic>.from(j['schedule'] as Map),
      ),
      reminder: ReminderConfig.fromJson(
        Map<String, dynamic>.from(j['reminder'] as Map),
      ),
      restrictions: Restrictions.fromJson(
        Map<String, dynamic>.from(j['restrictions'] as Map? ?? {}),
      ),
      status: CommitmentStatus.from(j['status'] as String),
      kind: CommitmentKind.from(j['kind'] as String?, verifier),
      reason: j['reason'] as String?,
    );
  }
}
