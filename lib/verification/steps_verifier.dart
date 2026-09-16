import 'dart:async';
import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/alarm_channel.dart';
import '../platform/steps_channel.dart';
import 'verifier.dart';

class StepsVerifier implements Verifier {
  final _events = StreamController<VerificationSignal>.broadcast();
  StreamSubscription<StepEvent>? _subscription;
  String? _attemptId;
  bool _satisfied = false;
  @override
  VerifierType get type => VerifierType.steps;
  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    if (config is! StepsConfig || config.validate() != null) {
      return VerifierAvailability(
        available: false,
        reason: config.validate() ?? 'Invalid step configuration',
      );
    }
    final p = await AlarmChannel.getPermissionStatus();
    if (!p.activityRecognition) {
      return const VerifierAvailability(
        available: false,
        missingPermissions: ['activityRecognition'],
        reason: 'Allow physical activity in permissions to record your steps.',
      );
    }
    try {
      final reading = await StepsChannel.getStepCount();
      return reading.available
          ? VerifierAvailability.ok
          : const VerifierAvailability(
              available: false,
              reason:
                  'This phone has no step counter. Choose arrival verification instead.',
            );
    } catch (e) {
      return VerifierAvailability(
        available: false,
        reason: 'Move a few steps and try again. $e',
      );
    }
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final cfg = config as StepsConfig;
    _attemptId = attempt.id;
    _satisfied = false;
    final reading = await StepsChannel.getStepCount();
    _subscription = StepsChannel.events()
        .where((e) => e.attemptId == attempt.id)
        .listen(
          (e) {
            if (e.type == 'sensor_lost') {
              _events.add(
                const VerificationSignal.cannotVerify(
                  'Unable to read the step counter. Check physical activity permission.',
                ),
              );
              return;
            }
            final p = (e.stepsSinceBaseline / cfg.targetSteps).clamp(0.0, 1.0);
            if (e.type == 'target_reached' &&
                e.elapsedMs >= cfg.minDurationMs &&
                !_satisfied) {
              _satisfied = true;
              _events.add(
                VerificationSignal.satisfied(
                  evidenceEnvelope(
                    verifier: type,
                    source: 'android_step_counter',
                    integrityFlags: const [
                      'monotonic_sensor',
                      'plausible_cadence',
                    ],
                    details: {
                      'stepsSinceBaseline': e.stepsSinceBaseline,
                      'elapsedMs': e.elapsedMs,
                      'baselineCapturedAt':
                          DateTime.now().millisecondsSinceEpoch - e.elapsedMs,
                    },
                  ),
                ),
              );
            } else if (!_satisfied) {
              _events.add(VerificationSignal.progressAt(p));
            }
          },
          onError: (Object e) => _events.add(
            const VerificationSignal.cannotVerify(
              'Step tracking stopped. Reopen permissions and try again.',
            ),
          ),
        );
    final started = await StepsChannel.startTracking(
      attemptId: attempt.id,
      baselineSteps: reading.cumulativeSteps,
      targetSteps: cfg.targetSteps,
    );
    if (!started) {
      throw StateError(
        'Android could not start step verification. Check battery and activity permissions.',
      );
    }
  }

  @override
  Stream<VerificationSignal> signals() => _events.stream;
  @override
  Future<void> disarm() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_attemptId != null) {
      await StepsChannel.stopTracking(_attemptId!);
      _attemptId = null;
    }
  }
}
