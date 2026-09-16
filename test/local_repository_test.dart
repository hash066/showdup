import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showdup/models/commitment.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/verifier_config.dart';
import 'package:showdup/services/repository.dart';
import 'package:timezone/data/latest.dart' as tz;

const _schedule = CommitmentSchedule(
  daysOfWeek: [2], // Tuesday
  windowStartLocal: '06:30',
  windowEndLocal: '09:00',
  timezone: 'Asia/Kolkata',
);

Map<String, dynamic> get _commitment => {
  'title': 'Morning walk',
  'verifierType': VerifierType.steps.wire,
  'verifierConfig': const StepsConfig(targetSteps: 500).toJson(),
  'schedule': _schedule.toJson(),
  'reminder': const ReminderConfig().toJson(),
  'restrictions': const Restrictions().toJson(),
};

Future<LocalRepository> _repository(DateTime now) async {
  final prefs = await SharedPreferences.getInstance();
  return LocalRepository(prefs, clock: () => now);
}

void main() {
  setUpAll(tz.initializeTimeZones);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'creates a pending local attempt once its scheduled window opens',
    () async {
      final repo = await _repository(DateTime.utc(2026, 9, 8, 2)); // 07:30 IST
      await repo.create(_commitment);

      final attempts = await repo.attempts().first;
      expect(attempts, hasLength(1));
      expect(attempts.single.date, '2026-09-08');
      expect(attempts.single.state, AttemptState.pending);
      await repo.close();
    },
  );

  test(
    'free tier gate updates immediately after a Pro entitlement refresh',
    () async {
      final repo = await _repository(DateTime.utc(2026, 9, 8, 2));
      await repo.create(_commitment);
      await expectLater(repo.create(_commitment), throwsStateError);

      await repo.setPro(true);
      await repo.create({..._commitment, 'title': 'Evening walk'});
      expect(await repo.commitments().first, hasLength(2));
      expect((await repo.profile().first).isPro, isTrue);
      await repo.close();
    },
  );

  test(
    'drafts schedule nothing and do not consume the free active slot',
    () async {
      final repo = await _repository(DateTime.utc(2026, 9, 8, 2));
      await repo.create({
        ..._commitment,
        'status': CommitmentStatus.draft.wire,
      });
      expect(
        (await repo.commitments().first).single.status,
        CommitmentStatus.draft,
      );
      expect(await repo.attempts().first, isEmpty);

      await repo.create({..._commitment, 'title': 'Active walk'});
      final commitments = await repo.commitments().first;
      expect(
        commitments.where((item) => item.status == CommitmentStatus.active),
        hasLength(1),
      );
      await expectLater(
        repo.update(commitments.first.id, {
          'status': CommitmentStatus.active.wire,
        }),
        throwsStateError,
      );
      await repo.close();
    },
  );

  test('downgrade keeps open attempts then pauses extra commitments', () async {
    var now = DateTime.utc(2026, 9, 8, 2);
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalRepository(prefs, clock: () => now);
    await repo.setPro(true);
    await repo.create(_commitment);
    await repo.create({..._commitment, 'title': 'Second walk'});

    await repo.setPro(false);
    expect(
      (await repo.commitments().first).where(
        (c) => c.status == CommitmentStatus.active,
      ),
      hasLength(2),
    );

    now = DateTime.utc(2026, 9, 8, 4); // 09:30 IST, after both windows.
    await repo.call('syncAttempts', {});
    final commitments = await repo.commitments().first;
    expect(
      commitments.where((c) => c.status == CommitmentStatus.active),
      hasLength(1),
    );
    expect(
      commitments.where((c) => c.status == CommitmentStatus.paused),
      hasLength(1),
    );
    await repo.close();
  });

  test(
    'advanced day windows require Pro and revert safely after expiry',
    () async {
      var now = DateTime.utc(2026, 9, 8, 13); // Tuesday, 18:30 IST.
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalRepository(prefs, clock: () => now);
      final advanced = {
        ..._commitment,
        'schedule': const CommitmentSchedule(
          daysOfWeek: [2],
          windowStartLocal: '06:30',
          windowEndLocal: '09:00',
          timezone: 'Asia/Kolkata',
          dayWindows: {2: DailyWindow(startLocal: '18:00', endLocal: '20:00')},
        ).toJson(),
      };

      await expectLater(repo.create(advanced), throwsStateError);
      await repo.setPro(true);
      await repo.create(advanced);
      expect((await repo.attempts().first).single.state, AttemptState.pending);

      await repo.setPro(false);
      expect(
        (await repo.commitments().first).single.schedule.hasCustomWindows,
        isTrue,
      );
      final commitment = (await repo.commitments().first).single;
      await repo.update(commitment.id, {'title': 'Renamed safely'});
      expect((await repo.commitments().first).single.title, 'Renamed safely');
      now = DateTime.utc(2026, 9, 8, 15); // 20:30 IST.
      await repo.call('syncAttempts', {});
      expect(
        (await repo.commitments().first).single.schedule.hasCustomWindows,
        isFalse,
      );
      await repo.close();
    },
  );

  test(
    'recovers a native completion exactly once after Flutter restarts',
    () async {
      final now = DateTime.utc(2026, 9, 8, 2);
      final repo = await _repository(now);
      await repo.create(_commitment);
      final attempt = (await repo.attempts().first).single;

      expect(
        await repo.recordNativeCompletion(attempt.id, {
          'completedAt': now.millisecondsSinceEpoch,
          'payload': {'steps': 550},
        }),
        isTrue,
      );
      expect(
        await repo.recordNativeCompletion(attempt.id, {
          'completedAt': now.millisecondsSinceEpoch,
          'payload': {'steps': 550},
        }),
        isTrue,
      );
      expect(
        (await repo.attempts().first).single.state,
        AttemptState.completed,
      );
      await repo.close();
    },
  );

  test('recovers a native verifier failure without breaking streak', () async {
    final now = DateTime.utc(2026, 9, 8, 2);
    final repo = await _repository(now);
    await repo.create(_commitment);
    final attempt = (await repo.attempts().first).single;

    expect(
      await repo.recordNativeFailure(attempt.id, {
        'type': 'steps',
        'reason': 'permission_denied',
        'failedAt': now.millisecondsSinceEpoch,
      }),
      isTrue,
    );

    final failed = (await repo.attempts().first).single;
    expect(failed.state, AttemptState.unverifiable);
    expect(failed.endedReason, EndedReason.verifierError);
    expect((await repo.profile().first).stats.currentStreak, 0);
    await repo.close();
  });

  test(
    'expires a pending attempt after an app restart past its window',
    () async {
      final initial = await _repository(DateTime.utc(2026, 9, 8, 2));
      await initial.create(_commitment);
      await initial.close();

      final prefs = await SharedPreferences.getInstance();
      final restarted = LocalRepository(
        prefs,
        clock: () => DateTime.utc(2026, 9, 8, 4), // 09:30 IST
      );
      await restarted.call('syncAttempts', {});
      final attempt = (await restarted.attempts().first).single;
      expect(attempt.state, AttemptState.expired);
      expect(attempt.endedReason, EndedReason.windowExpired);
      await restarted.close();
    },
  );

  test('backfills missed scheduled days after a restart', () async {
    final initial = await _repository(DateTime.utc(2026, 9, 8, 2));
    await initial.create({
      ..._commitment,
      'schedule': const CommitmentSchedule(
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
        windowStartLocal: '06:30',
        windowEndLocal: '09:00',
        timezone: 'Asia/Kolkata',
      ).toJson(),
    });
    await initial.close();

    final prefs = await SharedPreferences.getInstance();
    final restarted = LocalRepository(
      prefs,
      clock: () => DateTime.utc(2026, 9, 10, 5), // Thursday, 10:30 IST
    );
    await restarted.call('syncAttempts', {});
    final attempts = await restarted.attempts().first;
    expect(attempts, hasLength(3));
    expect(
      attempts.where((a) => a.state == AttemptState.expired),
      hasLength(3),
    );
    await restarted.close();
  });

  test(
    'retains two years for every Pro commitment, not 730 total rows',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final initial = LocalRepository(
        prefs,
        clock: () => DateTime.utc(2024, 9, 13, 5), // After the local window.
      );
      await initial.setPro(true);
      final daily = {
        ..._commitment,
        'schedule': const CommitmentSchedule(
          daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
          windowStartLocal: '06:30',
          windowEndLocal: '09:00',
          timezone: 'Asia/Kolkata',
        ).toJson(),
      };
      await initial.create(daily);
      await initial.create({...daily, 'title': 'Second daily walk'});
      await initial.close();

      final restarted = LocalRepository(
        prefs,
        clock: () => DateTime.utc(2026, 9, 12, 5),
      );
      await restarted.call('syncAttempts', {});
      final attempts = await restarted.attempts().first;

      expect(attempts.length, greaterThan(1400));
      expect(
        attempts.map((attempt) => attempt.commitmentId).toSet(),
        hasLength(2),
      );
      expect(
        attempts.every(
          (attempt) =>
              !attempt.windowEndAt.isBefore(DateTime.utc(2024, 9, 13, 5)),
        ),
        isTrue,
      );
      await restarted.close();
    },
  );

  test(
    'does not create a retroactive failure for an after-window commitment',
    () async {
      final repo = await _repository(DateTime.utc(2026, 9, 8, 5)); // 10:30 IST
      await repo.create(_commitment);
      expect(await repo.attempts().first, isEmpty);
      await repo.close();
    },
  );

  test('rejects schedule changes while an attempt is pending', () async {
    final repo = await _repository(DateTime.utc(2026, 9, 8, 2));
    await repo.create(_commitment);
    final commitment = (await repo.commitments().first).single;
    await expectLater(
      repo.update(commitment.id, {
        'schedule': const CommitmentSchedule(
          daysOfWeek: [2],
          windowStartLocal: '07:30',
          windowEndLocal: '09:00',
          timezone: 'Asia/Kolkata',
        ).toJson(),
      }),
      throwsStateError,
    );
    await repo.close();
  });

  test(
    'allows a material edit once a stale pending attempt is expired',
    () async {
      var now = DateTime.utc(2026, 9, 8, 2); // 07:30 IST
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalRepository(prefs, clock: () => now);
      await repo.create(_commitment);
      final commitment = (await repo.commitments().first).single;

      now = DateTime.utc(2026, 9, 8, 4); // 09:30 IST
      await repo.update(commitment.id, {
        'schedule': const CommitmentSchedule(
          daysOfWeek: [2],
          windowStartLocal: '07:30',
          windowEndLocal: '09:00',
          timezone: 'Asia/Kolkata',
        ).toJson(),
      });

      final attempt = (await repo.attempts().first).single;
      expect(attempt.state, AttemptState.expired);
      expect(
        (await repo.commitments().first).single.schedule.windowStartLocal,
        '07:30',
      );
      await repo.close();
    },
  );

  test('merges native reminder counts monotonically', () async {
    final repo = await _repository(DateTime.utc(2026, 9, 8, 2));
    await repo.create(_commitment);
    final attempt = (await repo.attempts().first).single;

    expect(
      await repo.recordReminderCounts({
        '${attempt.id}:fired': 2,
        '${attempt.id}:snoozed': 1,
      }),
      isTrue,
    );
    await repo.recordReminderCounts({
      '${attempt.id}:fired': 1,
      '${attempt.id}:snoozed': 3,
    });
    final updated = (await repo.attempts().first).single;
    expect(updated.remindersFired, 2);
    expect(updated.snoozes, 3);
    await repo.close();
  });

  test('recovers safely from corrupted persisted state', () async {
    SharedPreferences.setMockInitialValues({'localRepository.v1': '{broken'});
    final repo = await _repository(DateTime.utc(2026, 9, 8, 2));

    expect(await repo.commitments().first, isEmpty);
    await repo.create(_commitment);
    expect(await repo.commitments().first, hasLength(1));
    await repo.close();
  });

  test('deleteAccount clears all local product data', () async {
    final now = DateTime.utc(2026, 9, 8, 2);
    final repo = await _repository(now);
    await repo.setPro(true);
    await repo.create(_commitment);

    await repo.call('deleteAccount', {});

    expect(await repo.commitments().first, isEmpty);
    expect(await repo.attempts().first, isEmpty);
    expect((await repo.profile().first).isPro, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('localRepository.v1'), isFalse);
    await repo.close();
  });
}
