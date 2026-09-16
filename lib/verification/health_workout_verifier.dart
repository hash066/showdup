import 'dart:async';

import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/health_channel.dart';
import 'verifier.dart';

class HealthWorkoutVerifier implements Verifier {
  final _signals = StreamController<VerificationSignal>.broadcast();
  Timer? _poller;
  bool _satisfied = false;

  @override
  VerifierType get type => VerifierType.healthWorkout;

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    if (config is! HealthWorkoutConfig || config.validate() != null) {
      return VerifierAvailability(
        available: false,
        reason: config.validate() ?? 'Invalid workout configuration.',
      );
    }
    final health = await HealthChannel.availability();
    return health.available && health.permissionsGranted
        ? VerifierAvailability.ok
        : VerifierAvailability(
            available: false,
            missingPermissions: const ['health_connect_exercise'],
            reason:
                health.reason ??
                'Allow exercise-session and background-read access in Health Connect.',
          );
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final workout = config as HealthWorkoutConfig;
    _satisfied = false;
    Future<void> poll() async {
      if (_satisfied) return;
      try {
        final result = await HealthChannel.checkWorkout(
          startEpochMs: attempt.windowStartAt.millisecondsSinceEpoch,
          endEpochMs: attempt.windowEndAt.millisecondsSinceEpoch,
          targetDurationMs: workout.targetDurationMs,
          activityType: workout.activityType,
        );
        final progress = ((result['progress'] as num?)?.toDouble() ?? 0).clamp(
          0.0,
          1.0,
        );
        if (result['satisfied'] == true) {
          _satisfied = true;
          _signals.add(
            VerificationSignal.satisfied({
              'schemaVersion': 1,
              'verifier': type.wire,
              'source': result['sourcePackage'] ?? 'health_connect',
              'sourceLabel': result['sourceLabel'],
              'deviceType': result['deviceType'],
              'capturedAt': DateTime.now().millisecondsSinceEpoch,
              'integrityFlags': const [
                'sensor_recorded',
                'manual_and_unknown_excluded',
              ],
              'exerciseType': result['exerciseType'],
              'durationMs': result['durationMs'],
            }),
          );
        } else {
          _signals.add(VerificationSignal.progressAt(progress));
        }
      } catch (_) {
        // Background permission can reconnect; retry until the window ends.
      }
    }

    await poll();
    _poller = Timer.periodic(const Duration(seconds: 30), (_) => poll());
  }

  @override
  Stream<VerificationSignal> signals() => _signals.stream;

  @override
  Future<void> disarm() async {
    _poller?.cancel();
    _poller = null;
  }
}
