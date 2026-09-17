import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/models/commitment.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/presets.dart';
import 'package:showdup/models/verifier_config.dart';
import 'package:showdup/services/ladder_policy.dart';
import 'package:showdup/services/pro_nudge_policy.dart';
import 'package:showdup/services/repository.dart';
import 'package:showdup/services/rest_policy.dart';
import 'package:showdup/services/rhythm.dart';
import 'package:showdup/verification/leetcode_verifier.dart';
import 'package:showdup/verification/tag_scan_verifier.dart';
import 'package:showdup/verification/verifier.dart';
import 'package:timezone/data/latest.dart' as tz;

Attempt _attempt(
  int day,
  AttemptState state, {
  String commitmentId = 'c',
  Map<String, dynamic>? evidence,
}) {
  final start = DateTime.utc(2026, 9, day, 1);
  return Attempt(
    id: '${commitmentId}_2026-09-${day.toString().padLeft(2, '0')}',
    commitmentId: commitmentId,
    ownerUid: 'u',
    date: '2026-09-${day.toString().padLeft(2, '0')}',
    windowStartAt: start,
    windowEndAt: start.add(const Duration(hours: 2)),
    state: state,
    evidence: evidence,
  );
}

Commitment _commitment(VerifierConfig config, {CommitmentKind? kind}) =>
    Commitment(
      id: 'c',
      ownerUid: 'u',
      title: 'Test',
      verifierType: config.type,
      verifierConfig: config,
      schedule: const CommitmentSchedule(
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
        windowStartLocal: '06:30',
        windowEndLocal: '09:00',
        timezone: 'Asia/Kolkata',
      ),
      reminder: const ReminderConfig(),
      restrictions: const Restrictions(),
      status: CommitmentStatus.active,
      kind: kind ?? CommitmentKind.from(null, config.type),
    );

const _steps = CommitmentSchedule(
  daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
  windowStartLocal: '06:30',
  windowEndLocal: '09:00',
  timezone: 'Asia/Kolkata',
);

Map<String, dynamic> _stepsCommitment() => {
  'title': 'Walk 3,000 steps',
  'kind': CommitmentKind.steps.wire,
  'verifierType': VerifierType.steps.wire,
  'verifierConfig': const StepsConfig(targetSteps: 3000).toJson(),
  'schedule': _steps.toJson(),
  'reminder': const ReminderConfig().toJson(),
  'restrictions': const Restrictions().toJson(),
};

void main() {
  setUpAll(tz.initializeTimeZones);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('rest days', () {
    test('five show-ups earn one, capped at two', () {
      final attempts = [
        for (var d = 1; d <= 15; d++) _attempt(d, AttemptState.completed),
      ];
      final settled = RestPolicy.settle(const RestLedger(), attempts);
      expect(settled.ledger.banked, 2);
      expect(settled.ledger.progress, 0);
      // Settling again credits nothing twice.
      expect(RestPolicy.settle(settled.ledger, attempts).ledger.banked, 2);
    });

    test('a saved rest day covers the next miss, never an earlier one', () {
      final attempts = [
        _attempt(1, AttemptState.expired),
        for (var d = 2; d <= 6; d++) _attempt(d, AttemptState.completed),
        _attempt(7, AttemptState.expired),
        _attempt(8, AttemptState.expired),
      ];
      final settled = RestPolicy.settle(const RestLedger(), attempts);
      expect(settled.cover, {'c_2026-09-07': 'auto'});
      expect(settled.ledger.banked, 0);
    });

    test('planning spends a day and covers misses on that date', () {
      final ledger = RestPolicy.plan(
        const RestLedger(banked: 1),
        '2026-09-09',
      )!;
      expect(ledger.banked, 0);
      expect(RestPolicy.plan(ledger, '2026-09-10'), isNull);
      final settled = RestPolicy.settle(ledger, [
        _attempt(9, AttemptState.expired),
      ]);
      expect(settled.cover, {'c_2026-09-09': 'planned'});
    });

    test('rhythm leaves out rest days and phone trouble', () {
      final now = DateTime.utc(2026, 9, 10);
      final rhythm = Rhythm.of([
        _attempt(1, AttemptState.completed),
        _attempt(2, AttemptState.expired, evidence: const {'rest': 'auto'}),
        _attempt(3, AttemptState.unverifiable),
        _attempt(4, AttemptState.expired),
      ], now);
      expect(rhythm.counted, 2);
      expect(rhythm.percent, 50);
    });

    test('the repository covers a miss and keeps the streak', () async {
      var now = DateTime.utc(2026, 9, 1, 2);
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalRepository(prefs, clock: () => now, restDays: true);
      await repo.create(_stepsCommitment());
      for (var day = 1; day <= 5; day++) {
        now = DateTime.utc(2026, 9, day, 2);
        await repo.call('syncAttempts', {});
        await repo.recordNativeCompletion(
          (await repo.attempts().first).last.id,
          {'completedAt': now.millisecondsSinceEpoch, 'payload': {}},
        );
      }
      expect(repo.rest.banked, 1);

      now = DateTime.utc(2026, 9, 7, 2); // Day 6 missed entirely, day 7 open.
      await repo.call('syncAttempts', {});
      final attempts = await repo.attempts().first;
      final missed = attempts.firstWhere((a) => a.date == '2026-09-06');
      expect(missed.state, AttemptState.expired);
      expect(missed.restCovered, isTrue);
      expect(repo.rest.banked, 0);
      expect((await repo.profile().first).stats.currentStreak, 5);
      await repo.close();
    });

    test('ending today with a rest day needs one saved', () async {
      final now = DateTime.utc(2026, 9, 1, 2);
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalRepository(prefs, clock: () => now, restDays: true);
      await repo.create(_stepsCommitment());
      await expectLater(
        repo.call('endAttempt', {
          'commitmentId': (await repo.commitments().first).single.id,
          'date': '2026-09-01',
          'rest': true,
        }),
        throwsStateError,
      );
      await repo.close();
    });

    test('a planned rest day ends that day quietly', () async {
      var now = DateTime.utc(2026, 9, 1, 2);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'rest.v1',
        '{"banked":1,"progress":0,"startedAtMs":0}',
      );
      final repo = LocalRepository(prefs, clock: () => now, restDays: true);
      await repo.create(_stepsCommitment());
      expect(await repo.planRest('2026-09-02'), isTrue);
      expect(repo.plannedRestDates, ['2026-09-02']);
      now = DateTime.utc(2026, 9, 2, 2);
      await repo.call('syncAttempts', {});
      final tomorrow = (await repo.attempts().first).firstWhere(
        (a) => a.date == '2026-09-02',
      );
      expect(tomorrow.state, AttemptState.abandoned);
      expect(tomorrow.evidence?['rest'], 'planned');
      expect((await repo.profile().first).stats.currentStreak, 0);
      await repo.close();
    });
  });

  group('right-size ladder', () {
    test('six of seven offers a step up', () {
      final c = _commitment(
        const FocusConfig(packages: ['x'], targetDurationMs: 25 * 60000),
      );
      final attempts = [
        for (var d = 1; d <= 6; d++) _attempt(d, AttemptState.completed),
        _attempt(7, AttemptState.expired),
      ];
      final offer = LadderPolicy.offer(c, attempts)!;
      expect(offer.up, isTrue);
      expect((offer.config as FocusConfig).targetDurationMs, 30 * 60000);
      expect(offer.title, 'Focus for 30 minutes');
    });

    test('two misses in a row offers a step down, within bounds', () {
      final c = _commitment(const StepsConfig(targetSteps: 500));
      final down = LadderPolicy.offer(c, [
        _attempt(1, AttemptState.completed),
        _attempt(2, AttemptState.expired),
        _attempt(3, AttemptState.abandoned),
      ]);
      expect(down, isNull, reason: '500 is already the smallest step');
      final bigger = _commitment(const StepsConfig(targetSteps: 3000));
      final offer = LadderPolicy.offer(bigger, [
        _attempt(2, AttemptState.expired),
        _attempt(3, AttemptState.abandoned),
      ])!;
      expect(offer.up, isFalse);
      expect((offer.config as StepsConfig).targetSteps, 2500);
    });

    test('attempts before the current target and places are ignored', () {
      final focus = _commitment(
        const FocusConfig(packages: ['x'], targetDurationMs: 25 * 60000),
      );
      final attempts = [
        _attempt(1, AttemptState.expired),
        _attempt(2, AttemptState.expired),
      ];
      expect(
        LadderPolicy.offer(
          focus,
          attempts,
          targetSinceMs: DateTime.utc(2026, 9, 3).millisecondsSinceEpoch,
        ),
        isNull,
      );
      final gym = _commitment(
        const LocationConfig(lat: 19, lng: 72),
        kind: CommitmentKind.gym,
      );
      expect(LadderPolicy.offer(gym, attempts), isNull);
    });
  });

  group('free plan', () {
    test('location proofs need Pro and survive a downgrade paused', () async {
      final now = DateTime.utc(2026, 9, 1, 2);
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalRepository(prefs, clock: () => now);
      final gym = {
        ..._stepsCommitment(),
        'title': 'Gym session',
        'kind': CommitmentKind.gym.wire,
        'verifierType': VerifierType.location.wire,
        'verifierConfig': const LocationConfig(lat: 19, lng: 72).toJson(),
      };
      await expectLater(
        repo.create(gym),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            proProofMessage,
          ),
        ),
      );
      await repo.setPro(true);
      await repo.create(gym);
      await repo.setPro(false);
      now.add(const Duration(days: 1));
      expect(presetIsPro(CommitmentKind.gym), isTrue);
      expect(presetIsPro(CommitmentKind.steps), isFalse);
      await repo.close();
    });

    test('reach counts merge upward only', () async {
      final now = DateTime.utc(2026, 9, 1, 2);
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalRepository(prefs, clock: () => now);
      await repo.create(_stepsCommitment());
      final id = (await repo.attempts().first).single.id;
      await repo.recordReaches({id: 3, 'unknown_2026-09-01': 9});
      await repo.recordReaches({id: 2});
      expect(repo.reachesFor(id), 3);
      expect(repo.reachesFor('unknown_2026-09-01'), 0);
      await repo.close();
    });

    test('reaching for the held app is a nudge moment', () {
      expect(
        ProNudgePolicy.next(const [], isPro: false, reaches: 12)?.key,
        'reach:10',
      );
      expect(ProNudgePolicy.next(const [], isPro: true, reaches: 50), isNull);
    });
  });

  group('new proofs', () {
    final hash = 'a' * 64;
    final attempt = _attempt(1, AttemptState.pending);

    test('a matching tag scan completes; a different one does not', () async {
      final verifier = TagScanVerifier(scan: () async => hash);
      final signals = <VerificationSignal>[];
      final sub = verifier.signals().listen(signals.add);
      await verifier.arm(
        attempt,
        TagScanConfig(codeHash: hash, label: 'Mirror'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(signals.single.outcome, Outcome.satisfied);
      expect(signals.single.evidence['label'], 'Mirror');

      final wrong = TagScanVerifier(scan: () async => 'b' * 64);
      await expectLater(
        wrong.arm(attempt, TagScanConfig(codeHash: hash)),
        throwsStateError,
      );
      final cancelled = TagScanVerifier(scan: () async => null);
      await expectLater(
        cancelled.arm(attempt, TagScanConfig(codeHash: hash)),
        throwsStateError,
      );
      await sub.cancel();
    });

    test('tag configs keep only a hash', () {
      expect(const TagScanConfig(codeHash: 'not-a-hash').validate(), isNotNull);
      expect(TagScanConfig(codeHash: hash).validate(), isNull);
      expect(TagScanConfig(codeHash: hash).toJson().keys, ['codeHash']);
      expect(
        defaultTitle(
          CommitmentKind.tagScan,
          TagScanConfig(codeHash: hash, label: 'Kitchen'),
        ),
        'Scan in at Kitchen',
      );
    });

    test('LeetCode ownership codes are short and unambiguous', () {
      final code = LeetCodeVerifier.newOwnershipCode();
      expect(code, matches(RegExp(r'^showdup-[A-HJ-NP-Z2-9]{6}$')));
      expect(LeetCodeVerifier.newOwnershipCode(), isNot(code));
    });

    test('LeetCode polling backs off to five minutes', () {
      expect(LeetCodeVerifier.backoff(0), const Duration(seconds: 45));
      expect(LeetCodeVerifier.backoff(1), const Duration(seconds: 90));
      expect(LeetCodeVerifier.backoff(2), const Duration(seconds: 180));
      expect(LeetCodeVerifier.backoff(9), const Duration(minutes: 5));
    });

    test('ownership time survives a round trip and old configs still load', () {
      const config = LeetCodeConfig(username: 'ray', ownerVerifiedAtMs: 42);
      expect(LeetCodeConfig.fromJson(config.toJson()).ownerVerifiedAtMs, 42);
      expect(
        LeetCodeConfig.fromJson({'username': 'ray'}).ownerVerifiedAtMs,
        isNull,
      );
      expect(
        CommitmentKind.from(null, VerifierType.steps),
        CommitmentKind.steps,
      );
    });
  });

  test('a reason is optional, trimmed and bounded', () {
    final base = _commitment(const StepsConfig(targetSteps: 3000));
    final withReason = Commitment.fromJson('c', {
      ...base.toJson(),
      'reason': '  So I feel awake  ',
    });
    expect(withReason.toJson()['reason'], 'So I feel awake');
    expect(base.toJson().containsKey('reason'), isFalse);
    expect(
      Commitment.fromJson('c', {
        ...base.toJson(),
        'reason': 'x' * 121,
      }).validate(),
      isNotNull,
    );
  });

  test('unawaited futures are not left behind', () async {
    await Future<void>.delayed(Duration.zero);
    expect(Zone.current, isNotNull);
  });
}
