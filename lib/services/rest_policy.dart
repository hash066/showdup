import 'dart:math';

import '../models/attempt.dart';
import '../models/enums.dart';

/// Rest days: earn one for every five alarms you show up for, keep up to two.
/// A saved rest day covers a missed alarm automatically, or you can plan one.
class RestLedger {
  const RestLedger({
    this.banked = 0,
    this.progress = 0,
    this.startedAtMs = 0,
    this.counted = const {},
    this.settled = const {},
    this.plannedDates = const {},
  });

  static const perRest = 5;
  static const cap = 2;

  final int banked;

  /// Completions toward the next rest day, 0 to 4.
  final int progress;

  /// Attempts that ended before the ledger started are never touched.
  final int startedAtMs;
  final Set<String> counted;
  final Set<String> settled;

  /// Local dates (yyyy-MM-dd) someone chose to rest.
  final Set<String> plannedDates;

  RestLedger copyWith({
    int? banked,
    int? progress,
    Set<String>? counted,
    Set<String>? settled,
    Set<String>? plannedDates,
  }) => RestLedger(
    banked: banked ?? this.banked,
    progress: progress ?? this.progress,
    startedAtMs: startedAtMs,
    counted: counted ?? this.counted,
    settled: settled ?? this.settled,
    plannedDates: plannedDates ?? this.plannedDates,
  );

  Map<String, dynamic> toJson() => {
    'banked': banked,
    'progress': progress,
    'startedAtMs': startedAtMs,
    'counted': counted.toList(),
    'settled': settled.toList(),
    'plannedDates': plannedDates.toList(),
  };

  factory RestLedger.fromJson(Map<String, dynamic> j) => RestLedger(
    banked: ((j['banked'] as num?)?.toInt() ?? 0).clamp(0, cap),
    progress: ((j['progress'] as num?)?.toInt() ?? 0).clamp(0, perRest - 1),
    startedAtMs: (j['startedAtMs'] as num?)?.toInt() ?? 0,
    counted: {...(j['counted'] as List? ?? const []).whereType<String>()},
    settled: {...(j['settled'] as List? ?? const []).whereType<String>()},
    plannedDates: {
      ...(j['plannedDates'] as List? ?? const []).whereType<String>(),
    },
  );
}

class RestSettlement {
  const RestSettlement(this.ledger, this.cover);
  final RestLedger ledger;

  /// Attempt id to cover reason: `planned` or `auto`.
  final Map<String, String> cover;
}

class RestPolicy {
  const RestPolicy._();

  /// Walks finished attempts in time order: completions earn, misses spend.
  /// Idempotent: each attempt is credited or considered once.
  static RestSettlement settle(RestLedger ledger, Iterable<Attempt> attempts) {
    var banked = ledger.banked;
    var progress = ledger.progress;
    final counted = {...ledger.counted};
    final settled = {...ledger.settled};
    final cover = <String, String>{};
    final ordered =
        attempts
            .where(
              (a) => a.windowEndAt.millisecondsSinceEpoch >= ledger.startedAtMs,
            )
            .toList()
          ..sort((a, b) => a.windowEndAt.compareTo(b.windowEndAt));
    for (final attempt in ordered) {
      if (attempt.restCovered) continue;
      if (attempt.state == AttemptState.completed && counted.add(attempt.id)) {
        progress++;
        if (progress >= RestLedger.perRest) {
          progress = 0;
          banked = min(RestLedger.cap, banked + 1);
        }
      } else if (attempt.state == AttemptState.expired &&
          settled.add(attempt.id)) {
        if (ledger.plannedDates.contains(attempt.date)) {
          cover[attempt.id] = 'planned';
        } else if (banked > 0) {
          banked--;
          cover[attempt.id] = 'auto';
        }
      }
    }
    final known = {for (final a in attempts) a.id};
    return RestSettlement(
      ledger.copyWith(
        banked: banked,
        progress: progress,
        counted: counted.intersection(known),
        settled: settled.intersection(known),
      ),
      cover,
    );
  }

  /// Spends a saved rest day on a date. Returns null without one to spend.
  static RestLedger? plan(RestLedger ledger, String date) {
    if (ledger.plannedDates.contains(date)) return ledger;
    if (ledger.banked <= 0) return null;
    return ledger.copyWith(
      banked: ledger.banked - 1,
      plannedDates: {...ledger.plannedDates, date},
    );
  }

  /// Spends a saved rest day to end today. Returns null without one.
  static RestLedger? spend(RestLedger ledger) =>
      ledger.banked <= 0 ? null : ledger.copyWith(banked: ledger.banked - 1);
}
