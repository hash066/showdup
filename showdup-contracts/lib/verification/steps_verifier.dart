import 'dart:async';
import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import 'verifier.dart';

/// v1 verifier. Uses Sensor.TYPE_STEP_COUNTER via the steps platform
/// channel. Needs only ACTIVITY_RECOGNITION, which carries no Play
/// declaration burden.
///
/// AGENT 4: implement. The counter is cumulative since boot and RESETS
/// ON REBOOT. Detect the reset by comparing sensorBootTime and carry
/// forward already-credited steps. Losing a user's progress on reboot
/// is a one-star review.
class StepsVerifier implements Verifier {
  @override
  VerifierType get type => VerifierType.steps;

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) {
    throw UnimplementedError();
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) {
    throw UnimplementedError();
  }

  @override
  Stream<VerificationSignal> signals() {
    throw UnimplementedError();
  }

  @override
  Future<void> disarm() {
    throw UnimplementedError();
  }
}
