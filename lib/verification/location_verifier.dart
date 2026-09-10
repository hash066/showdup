import 'dart:async';
import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/alarm_channel.dart';
import '../platform/location_channel.dart';
import 'verifier.dart';

class LocationVerifier implements Verifier {
  final _events = StreamController<VerificationSignal>.broadcast();
  StreamSubscription<LocationEvent>? _subscription;
  String? _attemptId;
  LocationFix? _previous;
  bool _satisfied = false;
  @override
  VerifierType get type => VerifierType.location;
  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    if (config is! LocationConfig || config.validate() != null) {
      return VerifierAvailability(
        available: false,
        reason: config.validate() ?? 'Invalid location configuration',
      );
    }
    final p = await AlarmChannel.getPermissionStatus();
    return p.location
        ? VerifierAvailability.ok
        : const VerifierAvailability(
            available: false,
            missingPermissions: ['location'],
            reason:
                'Allow precise location while using the app. Then open this commitment to start verification.',
          );
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final cfg = config as LocationConfig;
    _attemptId = attempt.id;
    _satisfied = false;
    _previous = null;
    _subscription = LocationChannel.events()
        .where((e) => e.attemptId == attempt.id)
        .listen(
          (e) {
            if (e.type == 'unavailable') {
              _events.add(
                const VerificationSignal.cannotVerify(
                  'Location is unavailable. Check GPS and precise location permission.',
                ),
              );
              return;
            }
            final fix = e.fix;
            if (fix == null) return;
            if (fix.isMock || fix.accuracyM > cfg.radiusM) {
              _events.add(const VerificationSignal.progressAt(0));
              _previous = null;
              return;
            }
            if (e.type == 'dwell_satisfied' &&
                !_satisfied &&
                _previous != null) {
              _satisfied = true;
              _events.add(
                VerificationSignal.satisfied({
                  'lat': fix.lat,
                  'lng': fix.lng,
                  'accuracyM': fix.accuracyM,
                  'isMock': fix.isMock,
                  'epochMs': fix.epochMs,
                  'dwellMs': e.dwellMs,
                  'enteredAt': fix.epochMs - e.dwellMs,
                  'previousFix': {
                    'lat': _previous!.lat,
                    'lng': _previous!.lng,
                    'epochMs': _previous!.epochMs,
                  },
                }),
              );
            } else if (!_satisfied) {
              _events.add(
                VerificationSignal.progressAt(
                  (e.dwellMs / cfg.dwellMs).clamp(0.0, 1.0),
                ),
              );
            }
            _previous = fix;
          },
          onError: (Object e) => _events.add(
            const VerificationSignal.cannotVerify(
              'Location updates stopped. Check your permissions.',
            ),
          ),
        );
    final started = await LocationChannel.startWatch(
      attemptId: attempt.id,
      lat: cfg.lat,
      lng: cfg.lng,
      radiusM: cfg.radiusM,
      dwellMs: cfg.dwellMs,
      untilEpochMs: attempt.windowEndAt.millisecondsSinceEpoch,
    );
    if (!started) {
      throw StateError(
        'Location verification could not start. Check precise location and try again.',
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
      await LocationChannel.stopWatch(_attemptId!);
      _attemptId = null;
    }
  }
}
