import 'dart:async';
import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/alarm_channel.dart';
import '../platform/location_channel.dart';
import 'verifier.dart';

class WalkVerifier implements Verifier {
  final _events = StreamController<VerificationSignal>.broadcast();
  StreamSubscription<LocationEvent>? _subscription;
  String? _attemptId;
  bool _satisfied = false;

  @override
  VerifierType get type => VerifierType.walk;

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    if (config is! WalkConfig || config.validate() != null) {
      return VerifierAvailability(
        available: false,
        reason: config.validate() ?? 'Invalid walk configuration.',
      );
    }
    final permissions = await AlarmChannel.getPermissionStatus();
    return permissions.location
        ? VerifierAvailability.ok
        : const VerifierAvailability(
            available: false,
            missingPermissions: ['location'],
            reason:
                'Allow precise location while using ShowdUp to measure a walk.',
          );
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final walk = config as WalkConfig;
    _attemptId = attempt.id;
    _satisfied = false;
    _subscription = LocationChannel.events()
        .where((event) => event.attemptId == attempt.id)
        .listen((event) {
          if (event.type == 'unavailable') {
            _events.add(
              const VerificationSignal.cannotVerify(
                'Walk tracking stopped. Check precise location and battery settings.',
              ),
            );
            return;
          }
          final progress = switch (walk.mode) {
            WalkGoalMode.duration => event.dwellMs / walk.targetDurationMs,
            WalkGoalMode.distance => event.distanceM / walk.targetDistanceM,
            WalkGoalMode.destination => event.type == 'walk_satisfied' ? 1 : 0,
          };
          if (event.type == 'walk_satisfied' && !_satisfied) {
            _satisfied = true;
            _events.add(
              VerificationSignal.satisfied(
                evidenceEnvelope(
                  verifier: type,
                  source: 'android_fused_location',
                  integrityFlags: const [
                    'non_mock',
                    'plausible_speed',
                    'fresh_fix',
                  ],
                  details: {
                    'mode': walk.mode.wire,
                    'distanceM': event.distanceM,
                    'activeDurationMs': event.dwellMs,
                    if (event.fix != null) ...{
                      'lat': event.fix!.lat,
                      'lng': event.fix!.lng,
                      'accuracyM': event.fix!.accuracyM,
                      'isMock': event.fix!.isMock,
                      'epochMs': event.fix!.epochMs,
                    },
                  },
                ),
              ),
            );
          } else if (!_satisfied) {
            _events.add(
              VerificationSignal.progressAt(
                progress.clamp(0.0, 1.0).toDouble(),
              ),
            );
          }
        });
    final started = await LocationChannel.startWalk(
      attemptId: attempt.id,
      mode: walk.mode.wire,
      targetDurationMs: walk.targetDurationMs,
      targetDistanceM: walk.targetDistanceM,
      untilEpochMs: attempt.windowEndAt.millisecondsSinceEpoch,
      lat: walk.lat,
      lng: walk.lng,
    );
    if (!started) {
      throw StateError('Android could not start foreground walk tracking.');
    }
  }

  @override
  Stream<VerificationSignal> signals() => _events.stream;

  @override
  Future<void> disarm() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_attemptId != null) {
      await LocationChannel.stopWatch(_attemptId!);
      _attemptId = null;
    }
  }
}
