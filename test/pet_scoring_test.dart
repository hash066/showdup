import 'package:flutter_test/flutter_test.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/pet.dart';

Attempt attempt(
  String id,
  AttemptState state, {
  int snoozes = 0,
  int daysAgo = 0,
}) {
  final end = DateTime(2026, 9, 12).subtract(Duration(days: daysAgo));
  return Attempt(
    id: id,
    commitmentId: 'c',
    ownerUid: 'u',
    date: '2026-09-${(12 - daysAgo).toString().padLeft(2, '0')}',
    windowStartAt: end.subtract(const Duration(hours: 1)),
    windowEndAt: end,
    state: state,
    snoozes: snoozes,
    completedAt: state == AttemptState.completed ? end : null,
  );
}

void main() {
  test('completion loses five points per snooze with a floor of sixty', () {
    expect(PetScoring.attemptPoints(attempt('a', AttemptState.completed)), 100);
    expect(
      PetScoring.attemptPoints(
        attempt('b', AttemptState.completed, snoozes: 3),
      ),
      85,
    );
    expect(
      PetScoring.attemptPoints(
        attempt('c', AttemptState.completed, snoozes: 20),
      ),
      60,
    );
  });

  test('unverifiable attempts are excluded from normalized score', () {
    final attempts = [
      attempt('done', AttemptState.completed),
      attempt('miss', AttemptState.expired),
      attempt('sensor', AttemptState.unverifiable),
    ];
    expect(PetScoring.normalizedScore(attempts), 500);
    expect(PetScoring.normalizedScore(attempts, penalty: 100), 400);
  });

  test('misses never crack the companion or cost points', () {
    final attempts = [
      attempt('latest', AttemptState.expired),
      attempt('sensor', AttemptState.unverifiable, daysAgo: 1),
      attempt('second', AttemptState.abandoned, daysAgo: 2),
      attempt('third', AttemptState.expired, daysAgo: 3),
    ];
    expect(PetScoring.consecutiveMisses(attempts), 3);
    final mood = PetScoring.mood(recentAttempts: attempts, currentSnoozes: 0);
    expect(mood, PetMood.sad);
    expect(mood, isNot(PetMood.cracked));
    expect(PetScoring.normalizedScore(attempts), 0);
  });

  test('showing up right after a miss is a comeback', () {
    final attempts = [
      attempt('latest', AttemptState.completed),
      attempt('old', AttemptState.expired, daysAgo: 1),
      attempt('older', AttemptState.completed, daysAgo: 2),
    ];
    expect(PetScoring.consecutiveMisses(attempts), 0);
    expect(
      PetScoring.mood(recentAttempts: attempts, currentSnoozes: 1),
      PetMood.recovery,
    );
  });

  test('rest-covered misses neither score nor break a run', () {
    final rested = Attempt(
      id: 'rest',
      commitmentId: 'c',
      ownerUid: 'u',
      date: '2026-09-12',
      windowStartAt: DateTime(2026, 9, 12, 6),
      windowEndAt: DateTime(2026, 9, 12, 7),
      state: AttemptState.expired,
      evidence: const {'rest': 'auto'},
    );
    expect(PetScoring.eligible(rested), isFalse);
    expect(
      PetScoring.normalizedScore([
        rested,
        attempt('done', AttemptState.completed, daysAgo: 1),
      ]),
      1000,
    );
  });
}
