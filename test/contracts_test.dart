import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:showdup/core/scheduling.dart';
import 'package:showdup/models/commitment.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/verifier_config.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/verification/verifier.dart';
import 'package:showdup/verification/verifier_registry.dart';

class FakeVerifier implements Verifier {
  @override
  VerifierType get type => VerifierType.steps;
  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig c) async =>
      VerifierAvailability.ok;
  @override
  Future<void> arm(Attempt a, VerifierConfig c) async {}
  @override
  Future<void> disarm() async {}
  @override
  Stream<VerificationSignal> signals() =>
      Stream.value(const VerificationSignal.progressAt(.5));
}

void main() {
  setUpAll(tz.initializeTimeZones);
  const s = CommitmentSchedule(
    daysOfWeek: [1, 2, 3, 4, 5],
    windowStartLocal: '06:30',
    windowEndLocal: '09:00',
    timezone: 'Asia/Kolkata',
  );
  test('commitment timezone determines absolute window', () {
    final w = resolveWindow(s, DateTime(2026, 9, 8));
    expect(w.start, DateTime.utc(2026, 9, 8, 1));
    expect(w.end, DateTime.utc(2026, 9, 8, 3, 30));
  });
  test('weekend resolves next scheduled weekday', () {
    expect(
      nextWindow(s, DateTime.utc(2026, 9, 12, 12)),
      DateTime.utc(2026, 9, 14, 1),
    );
  });
  test('advanced schedule resolves a different window for each weekday', () {
    const advanced = CommitmentSchedule(
      daysOfWeek: [1, 2],
      windowStartLocal: '06:30',
      windowEndLocal: '09:00',
      timezone: 'Asia/Kolkata',
      dayWindows: {2: DailyWindow(startLocal: '18:00', endLocal: '20:00')},
    );
    final monday = resolveWindow(advanced, DateTime(2026, 9, 7));
    final tuesday = resolveWindow(advanced, DateTime(2026, 9, 8));
    expect(monday.start, DateTime.utc(2026, 9, 7, 1));
    expect(tuesday.start, DateTime.utc(2026, 9, 8, 12, 30));
    expect(
      CommitmentSchedule.fromJson(advanced.toJson()).dayWindows[2]?.endLocal,
      '20:00',
    );
  });
  test('reminder count, spacing and terminal cancellation', () {
    final w = resolveWindow(s, DateTime(2026, 9, 8));
    final times = reminderTimes(w.start, w.end, const ReminderConfig());
    expect(times.length, 6);
    expect(times[1].difference(times[0]), const Duration(minutes: 20));
    expect(
      reminderTimes(w.start, w.end, const ReminderConfig(), terminal: true),
      isEmpty,
    );
  });
  test('unverifiable preserves streak, abandoned and expired break it', () {
    expect(AttemptState.unverifiable.breaksStreak, false);
    expect(AttemptState.expired.breaksStreak, true);
    expect(AttemptState.abandoned.breaksStreak, true);
  });
  test('invalid config includes nonfinite coordinates and negative times', () {
    expect(
      const LocationConfig(lat: double.nan, lng: 10).validate(),
      isNotNull,
    );
    expect(const StepsConfig(targetSteps: 199).validate(), isNotNull);
    expect(
      const CommitmentSchedule(
        daysOfWeek: [1],
        windowStartLocal: '-1:30',
        windowEndLocal: '09:00',
        timezone: 'Asia/Kolkata',
      ).validate(),
      isNotNull,
    );
    expect(
      const CommitmentSchedule(
        daysOfWeek: [1],
        windowStartLocal: '06:30',
        windowEndLocal: '09:00',
        timezone: 'Asia/Kolkata',
        dayWindows: {2: DailyWindow(startLocal: '08:00', endLocal: '09:00')},
      ).validate(),
      isNotNull,
    );
  });
  test('commitment presets migrate safely and place metadata round-trips', () {
    // Steps is its own preset again in 1.0.
    expect(CommitmentKind.from(null, VerifierType.steps), CommitmentKind.steps);
    expect(
      CommitmentKind.from(null, VerifierType.location),
      CommitmentKind.gym,
    );
    const gym = LocationConfig(
      lat: 12.9716,
      lng: 77.5946,
      radiusM: 150,
      dwellMs: 300000,
      label: 'My gym',
      placeId: 'place-1',
      address: 'Bengaluru',
    );
    final restored = LocationConfig.fromJson(gym.toJson());
    expect(restored.radiusM, 150);
    expect(restored.dwellMs, 300000);
    expect(restored.placeId, 'place-1');
    expect(restored.address, 'Bengaluru');
    expect(
      const WalkConfig(
        mode: WalkGoalMode.duration,
        targetDurationMs: 4 * 60000,
      ).validate(),
      isNotNull,
    );
    expect(
      const WalkConfig(
        mode: WalkGoalMode.distance,
        targetDistanceM: 1000,
      ).validate(),
      isNull,
    );
    expect(
      const WalkConfig(mode: WalkGoalMode.destination).validate(),
      isNotNull,
    );
  });
  test(
    'new verified preset contracts round-trip without changing old wires',
    () {
      const focus = FocusConfig(
        packages: ['com.example.distraction'],
        targetDurationMs: 25 * 60000,
      );
      const workout = HealthWorkoutConfig(
        activityType: 'running',
        targetDurationMs: 30 * 60000,
      );
      const leetcode = LeetCodeConfig(username: 'hash_066', targetAccepted: 2);
      expect(
        VerifierConfig.fromJson(VerifierType.focus.wire, focus.toJson()),
        isA<FocusConfig>(),
      );
      expect(
        VerifierConfig.fromJson(
          VerifierType.healthWorkout.wire,
          workout.toJson(),
        ),
        isA<HealthWorkoutConfig>(),
      );
      expect(
        (VerifierConfig.fromJson(VerifierType.leetcode.wire, leetcode.toJson())
                as LeetCodeConfig)
            .targetAccepted,
        2,
      );
      expect(CommitmentStatus.from('draft'), CommitmentStatus.draft);
      expect(
        const FocusConfig(packages: []).validate(),
        'Choose at least one distracting app.',
      );
      expect(
        const HealthWorkoutConfig(activityType: 'manual').validate(),
        isNotNull,
      );
      expect(
        const LeetCodeConfig(username: 'bad username').validate(),
        isNotNull,
      );
      expect(VerifierType.walk.wire, 'walk');
      expect(CommitmentKind.gym.wire, 'gym');
    },
  );
  test(
    'verifier registry accepts independent implementation unchanged',
    () async {
      final v = VerifierRegistry(
        overrides: {VerifierType.steps: FakeVerifier.new},
      ).create(VerifierType.steps);
      expect(
        (await v.checkAvailability(
          const StepsConfig(targetSteps: 200),
        )).available,
        true,
      );
      expect((await v.signals().first).progress, .5);
      await v.disarm();
      await v.disarm();
    },
  );
}
