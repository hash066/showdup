import 'attempt.dart';
import 'enums.dart';

/// Companion characters. Wire values are persisted locally and in Battles.
enum MascotId {
  /// The brand dot with a face. Free for everyone and the default.
  dot('dot', '●', 'Dot'),
  fox('fox', '🦊', 'Fox'),
  cat('cat', '🐱', 'Cat'),
  puppy('puppy', '🐶', 'Pup'),
  penguin('penguin', '🐧', 'Penguin'),
  capybara('capybara', '🦫', 'Capybara');

  const MascotId(this.wire, this.fallbackGlyph, this.label);
  final String wire;
  final String fallbackGlyph;
  final String label;

  /// Illustrated animals unlock with ShowdUp Pro.
  bool get isPremium => this != MascotId.dot;

  static MascotId fromWire(String? value) => values.firstWhere(
    (item) => item.wire == value,
    orElse: () => MascotId.dot,
  );
}

enum PetMood {
  happy('happy'),
  uneasy('uneasy'),
  sad('sad'),
  cracked('cracked'),
  recovery('recovery');

  const PetMood(this.wire);
  final String wire;
}

class PetSnapshot {
  const PetSnapshot({
    required this.mascot,
    required this.mood,
    required this.weeklyScore,
    required this.todayCompleted,
    required this.todayTotal,
    required this.streak,
    required this.consecutiveMisses,
    required this.burstCount,
    this.activeAttemptId,
    this.activeTitle,
    this.nextAlarmAt,
    this.rank,
    this.friendGlyphs = const [],
    this.topRanks = const [],
  });

  final MascotId mascot;
  final PetMood mood;
  final int weeklyScore;
  final int todayCompleted;
  final int todayTotal;
  final int streak;
  final int consecutiveMisses;
  final int burstCount;
  final String? activeAttemptId;
  final String? activeTitle;
  final DateTime? nextAlarmAt;
  final int? rank;
  final List<String> friendGlyphs;
  final List<Map<String, dynamic>> topRanks;

  Map<String, dynamic> toJson() => {
    'mascot': mascot.wire,
    'mascotGlyph': mascot.fallbackGlyph,
    'mood': mood.wire,
    'weeklyScore': weeklyScore,
    'todayCompleted': todayCompleted,
    'todayTotal': todayTotal,
    'streak': streak,
    'consecutiveMisses': consecutiveMisses,
    'burstCount': burstCount,
    'activeAttemptId': activeAttemptId,
    'activeTitle': activeTitle,
    'nextAlarmEpochMs': nextAlarmAt?.millisecondsSinceEpoch,
    'rank': rank,
    'friendGlyphs': friendGlyphs.take(3).toList(),
    'topRanks': topRanks.take(5).toList(),
  };
}

class PetScoring {
  const PetScoring._();

  static bool eligible(Attempt attempt) =>
      attempt.state != AttemptState.pending &&
      attempt.state != AttemptState.unverifiable;

  static int attemptPoints(Attempt attempt) {
    if (attempt.state != AttemptState.completed) return 0;
    return (100 - attempt.snoozes * 5).clamp(60, 100);
  }

  static int normalizedScore(Iterable<Attempt> attempts, {int penalty = 0}) {
    final eligibleAttempts = attempts.where(eligible).toList();
    if (eligibleAttempts.isEmpty) return 0;
    final earned = eligibleAttempts.fold<int>(
      0,
      (sum, a) => sum + attemptPoints(a),
    );
    return ((earned / (eligibleAttempts.length * 100) * 1000).round() - penalty)
        .clamp(0, 1000);
  }

  static int consecutiveMisses(Iterable<Attempt> attempts) {
    final terminal =
        attempts
            .where(
              (a) => a.state.isTerminal && a.state != AttemptState.unverifiable,
            )
            .toList()
          ..sort((a, b) => b.windowEndAt.compareTo(a.windowEndAt));
    var count = 0;
    for (final attempt in terminal) {
      if (attempt.state == AttemptState.completed) break;
      if (attempt.state == AttemptState.abandoned ||
          attempt.state == AttemptState.expired) {
        count++;
      }
    }
    return count;
  }

  static PetMood mood({
    required Iterable<Attempt> recentAttempts,
    required int currentSnoozes,
    required bool cracked,
  }) {
    if (cracked) return PetMood.cracked;
    final eligibleAttempts = recentAttempts.where(eligible).toList();
    final ratio = eligibleAttempts.isEmpty
        ? 1.0
        : eligibleAttempts
                  .where((a) => a.state == AttemptState.completed)
                  .length /
              eligibleAttempts.length;
    final misses = consecutiveMisses(recentAttempts);
    if (misses >= 2 || currentSnoozes >= 2 || ratio < .6) return PetMood.sad;
    if (currentSnoozes == 1 || ratio < .8) return PetMood.uneasy;
    return PetMood.happy;
  }
}
