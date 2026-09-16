import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';

Map<String, dynamic> evidenceEnvelope({
  required VerifierType verifier,
  required String source,
  required Map<String, dynamic> details,
  List<String> integrityFlags = const [],
}) => {
  'schemaVersion': 1,
  'verifier': verifier.wire,
  'source': source,
  'capturedAt': DateTime.now().millisecondsSinceEpoch,
  'integrityFlags': integrityFlags,
  ...details,
};

enum Outcome { progress, satisfied, unverifiable }

class VerificationSignal {
  const VerificationSignal({
    required this.outcome,
    this.progress = 0,
    this.evidence = const {},
    this.failureReason,
  });

  final Outcome outcome;

  /// 0..1, drives the UI ring.
  final double progress;

  /// Sent to submitEvidence. Must never contain a completion time;
  /// the server stamps that.
  final Map<String, dynamic> evidence;

  /// Set only when outcome == unverifiable. Surfaced as
  /// "Unable to verify", never as failure.
  final String? failureReason;

  const VerificationSignal.progressAt(
    double p, {
    Map<String, dynamic> e = const {},
  }) : this(outcome: Outcome.progress, progress: p, evidence: e);

  const VerificationSignal.satisfied(Map<String, dynamic> e)
    : this(outcome: Outcome.satisfied, progress: 1, evidence: e);

  const VerificationSignal.cannotVerify(String reason)
    : this(outcome: Outcome.unverifiable, failureReason: reason);
}

class VerifierAvailability {
  const VerifierAvailability({
    required this.available,
    this.missingPermissions = const [],
    this.reason,
  });

  final bool available;
  final List<String> missingPermissions;
  final String? reason;

  static const ok = VerifierAvailability(available: true);
}

/// FROZEN CONTRACT. A new verifier must implement exactly this and
/// nothing else in the app should need to change.
abstract class Verifier {
  VerifierType get type;

  /// Hardware, permissions, config sanity. Called before saving a
  /// commitment and again when the window opens.
  Future<VerifierAvailability> checkAvailability(VerifierConfig config);

  /// Window opened. Capture any baseline needed (step counter value,
  /// first location fix) and start listening.
  Future<void> arm(Attempt attempt, VerifierConfig config);

  /// Progress and completion. Emits at most one satisfied signal.
  Stream<VerificationSignal> signals();

  /// Verified, window closed, or user ended. Must be safe to call twice.
  Future<void> disarm();
}
