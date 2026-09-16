import 'dart:async';

import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/blocker_channel.dart';
import 'verifier.dart';

class FocusVerifier implements Verifier {
  final _signals = StreamController<VerificationSignal>.broadcast();
  Timer? _poller;
  String? _attemptId;
  bool _satisfied = false;

  @override
  VerifierType get type => VerifierType.focus;

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    if (config is! FocusConfig || config.validate() != null) {
      return VerifierAvailability(
        available: false,
        reason: config.validate() ?? 'Invalid Focus configuration.',
      );
    }
    final status = await BlockerChannel.status();
    return status.accessibilityEnabled
        ? VerifierAvailability.ok
        : const VerifierAvailability(
            available: false,
            missingPermissions: ['accessibility'],
            reason:
                'Enable ShowdUp accessibility access to verify selected apps. It never reads screen contents or typed text.',
          );
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final focus = config as FocusConfig;
    _attemptId = attempt.id;
    _satisfied = false;
    final started = await BlockerChannel.startFocus(
      attemptId: attempt.id,
      packages: focus.packages,
      startEpochMs: attempt.windowStartAt.millisecondsSinceEpoch,
      endEpochMs: attempt.windowEndAt.millisecondsSinceEpoch,
      targetDurationMs: focus.targetDurationMs,
      graceSeconds: focus.graceSeconds,
    );
    if (!started) {
      throw StateError('Android could not start Focus verification.');
    }
    Future<void> poll() async {
      if (_satisfied || _attemptId == null) return;
      try {
        final status = await BlockerChannel.focusStatus(attempt.id);
        if (status['failed'] == true) {
          _signals.add(
            const VerificationSignal.cannotVerify(
              'Accessibility access stopped during Focus verification.',
            ),
          );
          return;
        }
        final progress = ((status['progress'] as num?)?.toDouble() ?? 0).clamp(
          0.0,
          1.0,
        );
        if (status['completed'] == true) {
          _satisfied = true;
          _signals.add(
            VerificationSignal.satisfied({
              'schemaVersion': 1,
              'verifier': type.wire,
              'source': 'android_accessibility_window_events',
              'capturedAt': DateTime.now().millisecondsSinceEpoch,
              'integrityFlags': const ['no_window_content', 'ten_second_grace'],
              'targetDurationMs': focus.targetDurationMs,
              'resetCount': (status['resetCount'] as num?)?.toInt() ?? 0,
            }),
          );
        } else {
          _signals.add(VerificationSignal.progressAt(progress));
        }
      } catch (_) {
        // Accessibility may reconnect; native state remains durable.
      }
    }

    await poll();
    _poller = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  @override
  Stream<VerificationSignal> signals() => _signals.stream;

  @override
  Future<void> disarm() async {
    _poller?.cancel();
    _poller = null;
    final id = _attemptId;
    _attemptId = null;
    if (id != null) await BlockerChannel.stopFocus(id);
  }
}
