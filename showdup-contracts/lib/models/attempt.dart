import 'enums.dart';

class Attempt {
  const Attempt({
    required this.id,
    required this.commitmentId,
    required this.ownerUid,
    required this.date,
    required this.windowStartAt,
    required this.windowEndAt,
    required this.state,
    this.remindersFired = 0,
    this.snoozes = 0,
    this.completedAt,
    this.evidence,
    this.endedReason,
  });

  final String id;
  final String commitmentId;
  final String ownerUid;
  final String date; // local date "2026-09-12"
  final DateTime windowStartAt;
  final DateTime windowEndAt;
  final AttemptState state;
  final int remindersFired;
  final int snoozes;

  /// SERVER STAMPED ONLY. The client must never set or send this.
  final DateTime? completedAt;
  final Map<String, dynamic>? evidence;
  final EndedReason? endedReason;

  bool get isWindowOpen {
    final now = DateTime.now();
    return now.isAfter(windowStartAt) && now.isBefore(windowEndAt);
  }

  /// Client writes are denied by rules; this exists only for tests
  /// and for the emulator seed.
  Map<String, dynamic> toJson() => {
        'commitmentId': commitmentId,
        'ownerUid': ownerUid,
        'date': date,
        'windowStartAt': windowStartAt.toUtc().toIso8601String(),
        'windowEndAt': windowEndAt.toUtc().toIso8601String(),
        'state': state.wire,
        'remindersFired': remindersFired,
        'snoozes': snoozes,
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        if (evidence != null) 'evidence': evidence,
        if (endedReason != null) 'endedReason': endedReason!.wire,
      };

  factory Attempt.fromJson(String id, Map<String, dynamic> j) => Attempt(
        id: id,
        commitmentId: j['commitmentId'] as String,
        ownerUid: j['ownerUid'] as String,
        date: j['date'] as String,
        windowStartAt: _dt(j['windowStartAt'])!,
        windowEndAt: _dt(j['windowEndAt'])!,
        state: AttemptState.from(j['state'] as String),
        remindersFired: (j['remindersFired'] as num?)?.toInt() ?? 0,
        snoozes: (j['snoozes'] as num?)?.toInt() ?? 0,
        completedAt: _dt(j['completedAt']),
        evidence: j['evidence'] == null
            ? null
            : Map<String, dynamic>.from(j['evidence'] as Map),
        endedReason: j['endedReason'] == null
            ? null
            : EndedReason.from(j['endedReason'] as String),
      );

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.parse(v).toLocal();
    // Firestore Timestamp, duck typed so this file needs no firebase import.
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
