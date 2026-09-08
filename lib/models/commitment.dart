import 'enums.dart';
import 'verifier_config.dart';

class CommitmentSchedule {
  const CommitmentSchedule({
    required this.daysOfWeek,
    required this.windowStartLocal,
    required this.windowEndLocal,
    required this.timezone,
  });

  /// ISO weekdays, 1 = Monday .. 7 = Sunday.
  final List<int> daysOfWeek;
  final String windowStartLocal; // "06:30"
  final String windowEndLocal; // "09:00"
  final String timezone; // IANA, e.g. "Asia/Kolkata"

  String? validate() {
    if (daysOfWeek.isEmpty) return 'Pick at least one day.';
    if (daysOfWeek.any((d) => d < 1 || d > 7)) return 'Invalid weekday.';
    final s = _mins(windowStartLocal), e = _mins(windowEndLocal);
    if (s == null || e == null) return 'Times must be HH:mm.';
    if (e <= s) return 'Window must end after it starts.';
    if (e - s < 15) return 'Window must be at least 15 minutes.';
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

  Map<String, dynamic> toJson() => {
    'daysOfWeek': daysOfWeek,
    'windowStartLocal': windowStartLocal,
    'windowEndLocal': windowEndLocal,
    'timezone': timezone,
  };

  factory CommitmentSchedule.fromJson(Map<String, dynamic> j) =>
      CommitmentSchedule(
        daysOfWeek: (j['daysOfWeek'] as List).map((e) => e as int).toList(),
        windowStartLocal: j['windowStartLocal'] as String,
        windowEndLocal: j['windowEndLocal'] as String,
        timezone: j['timezone'] as String,
      );
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
    if (maxReminders < 1 || maxReminders > 20) {
      return 'Reminders must be between 1 and 20.';
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

  String? validate() =>
      verifierConfig.validate() ??
      schedule.validate() ??
      reminder.validate() ??
      (title.trim().isEmpty ? 'Give it a name.' : null);

  Map<String, dynamic> toJson() => {
    'ownerUid': ownerUid,
    'title': title,
    'verifierType': verifierType.wire,
    'verifierConfig': verifierConfig.toJson(),
    'schedule': schedule.toJson(),
    'reminder': reminder.toJson(),
    'restrictions': restrictions.toJson(),
    'status': status.wire,
  };

  factory Commitment.fromJson(String id, Map<String, dynamic> j) => Commitment(
    id: id,
    ownerUid: j['ownerUid'] as String,
    title: j['title'] as String,
    verifierType: VerifierType.from(j['verifierType'] as String),
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
  );
}
