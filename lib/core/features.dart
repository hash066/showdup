import '../models/enums.dart';

/// Compile-time feature switches, set with `--dart-define=FEATURE_X=true`.
///
/// Unfinished or policy-gated features default to off so every build stays
/// shippable while the redesign lands in small steps.
class Features {
  Features._();

  /// The catch: hold a chosen app until proof. Off until the patent decision
  /// clears, because closed-test builds count as disclosure.
  static const catchEnabled = bool.fromEnvironment('FEATURE_CATCH');

  static const restDays = bool.fromEnvironment('FEATURE_REST_DAYS');
  static const ladder = bool.fromEnvironment('FEATURE_LADDER');

  /// LeetCode verification ships in 1.0 as a beta.
  static const leetcode = bool.fromEnvironment(
    'FEATURE_LEETCODE',
    defaultValue: true,
  );

  static const overlay = bool.fromEnvironment(
    'FEATURE_OVERLAY',
    defaultValue: true,
  );

  /// Health Connect workouts move to 1.1; the release manifest no longer
  /// declares Health Connect permissions.
  static const workout = bool.fromEnvironment('FEATURE_WORKOUT');

  static bool presetEnabled(CommitmentKind kind) => switch (kind) {
    CommitmentKind.workout => workout,
    CommitmentKind.leetcode => leetcode,
    _ => true,
  };
}
