import 'package:intl/intl.dart';

import 'enums.dart';
import 'verifier_config.dart';

/// Proofs that need ShowdUp Pro. Location-based proof is the most wanted,
/// and place search has a per-use cost.
bool presetIsPro(CommitmentKind kind) => switch (kind) {
  CommitmentKind.walk || CommitmentKind.gym || CommitmentKind.arrive => true,
  _ => false,
};

bool verifierIsPro(VerifierType type) =>
    type == VerifierType.location || type == VerifierType.walk;

/// The name an alarm gets from its preset and goal.
String defaultTitle(
  CommitmentKind kind,
  VerifierConfig config,
) => switch (config) {
  StepsConfig(:final targetSteps) =>
    'Walk ${NumberFormat.decimalPattern().format(targetSteps)} steps',
  TagScanConfig(:final label) =>
    label?.isNotEmpty == true ? 'Scan in at $label' : 'Scan my tag',
  LocationConfig() when kind == CommitmentKind.gym => 'Gym session',
  LocationConfig(:final label) =>
    'Arrive at ${label?.isNotEmpty == true ? label : 'my place'}',
  FocusConfig(:final targetDurationMs) =>
    'Focus for ${targetDurationMs ~/ 60000} minutes',
  HealthWorkoutConfig(:final targetDurationMs) =>
    'Workout for ${targetDurationMs ~/ 60000} minutes',
  LeetCodeConfig(:final targetAccepted) =>
    'Solve $targetAccepted LeetCode problem${targetAccepted == 1 ? '' : 's'}',
  WalkConfig(mode: WalkGoalMode.duration, :final targetDurationMs) =>
    'Walk for ${targetDurationMs ~/ 60000} minutes',
  WalkConfig(mode: WalkGoalMode.distance, :final targetDistanceM) =>
    'Walk ${(targetDistanceM / 1000).toStringAsFixed(targetDistanceM % 1000 == 0 ? 0 : 2)} km',
  WalkConfig(:final label) =>
    'Walk to ${label?.isNotEmpty == true ? label : 'my destination'}',
};
