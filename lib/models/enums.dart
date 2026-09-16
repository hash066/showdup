/// FROZEN CONTRACT. String values are persisted; never rename them.
library;

enum VerifierType {
  steps('steps'),
  location('location'),
  walk('walk'),
  focus('focus'),
  healthWorkout('health_workout'),
  leetcode('leetcode');

  const VerifierType(this.wire);
  final String wire;
  static VerifierType from(String s) =>
      VerifierType.values.firstWhere((e) => e.wire == s);
}

enum WalkGoalMode {
  duration('duration'),
  distance('distance'),
  destination('destination');

  const WalkGoalMode(this.wire);
  final String wire;
  static WalkGoalMode from(String? value) => WalkGoalMode.values.firstWhere(
    (mode) => mode.wire == value,
    orElse: () => WalkGoalMode.duration,
  );
}

/// Product-level presets. Users choose one of these instead of composing an
/// arbitrary title and verifier. The wire value is stored locally so future
/// presets can evolve without guessing from the verifier type.
enum CommitmentKind {
  walk('walk'),
  gym('gym'),
  arrive('arrive'),
  focus('focus'),
  workout('workout'),
  leetcode('leetcode');

  const CommitmentKind(this.wire);
  final String wire;

  static CommitmentKind from(String? value, VerifierType verifier) {
    for (final kind in CommitmentKind.values) {
      if (kind.wire == value) return kind;
    }
    return switch (verifier) {
      VerifierType.location => CommitmentKind.gym,
      VerifierType.focus => CommitmentKind.focus,
      VerifierType.healthWorkout => CommitmentKind.workout,
      VerifierType.leetcode => CommitmentKind.leetcode,
      _ => CommitmentKind.walk,
    };
  }
}

enum AttemptState {
  pending('pending'),
  completed('completed'),
  abandoned('abandoned'),
  expired('expired'),
  unverifiable('unverifiable');

  const AttemptState(this.wire);
  final String wire;
  static AttemptState from(String s) =>
      AttemptState.values.firstWhere((e) => e.wire == s);

  bool get isTerminal => this != AttemptState.pending;

  /// Only completion counts toward a streak. unverifiable must NOT break it.
  bool get breaksStreak =>
      this == AttemptState.expired || this == AttemptState.abandoned;
}

enum EndedReason {
  verified('verified'),
  userEnded('user_ended'),
  windowExpired('window_expired'),
  verifierError('verifier_error');

  const EndedReason(this.wire);
  final String wire;
  static EndedReason from(String s) =>
      EndedReason.values.firstWhere((e) => e.wire == s);
}

enum CommitmentStatus {
  active('active'),
  draft('draft'),
  paused('paused'),
  archived('archived');

  const CommitmentStatus(this.wire);
  final String wire;
  static CommitmentStatus from(String s) =>
      CommitmentStatus.values.firstWhere((e) => e.wire == s);
}

enum VolumeMode {
  gentle('gentle'),
  loud('loud');

  const VolumeMode(this.wire);
  final String wire;
  static VolumeMode from(String s) =>
      VolumeMode.values.firstWhere((e) => e.wire == s);
}
