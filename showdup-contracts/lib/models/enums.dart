/// FROZEN CONTRACT. String values are persisted; never rename them.

enum VerifierType {
  steps('steps'),
  location('location');

  const VerifierType(this.wire);
  final String wire;
  static VerifierType from(String s) =>
      VerifierType.values.firstWhere((e) => e.wire == s);
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
