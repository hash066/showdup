import 'dart:convert';
import 'dart:math';

import '../models/attempt.dart';
import '../models/commitment.dart';
import '../models/enums.dart';
import '../models/presets.dart';
import '../models/verifier_config.dart';

class LadderOffer {
  const LadderOffer({
    required this.commitmentId,
    required this.up,
    required this.config,
    required this.title,
    required this.change,
  });

  final String commitmentId;
  final bool up;
  final VerifierConfig config;

  /// The alarm's new name, like "Walk for 20 minutes".
  final String title;

  /// A short phrase for the offer, like "20 minutes".
  final String change;
}

/// Right-size the goal. Six of the last seven at this target means it may be
/// too easy; two misses in a row means it may be too big. Never automatic.
class LadderPolicy {
  const LadderPolicy._();

  static LadderOffer? offer(
    Commitment commitment,
    Iterable<Attempt> attempts, {
    int targetSinceMs = 0,
  }) {
    final eligible =
        attempts
            .where(
              (a) =>
                  a.commitmentId == commitment.id &&
                  a.state.isTerminal &&
                  a.state != AttemptState.unverifiable &&
                  !a.restCovered &&
                  a.windowStartAt.millisecondsSinceEpoch >= targetSinceMs,
            )
            .toList()
          ..sort((a, b) => b.windowEndAt.compareTo(a.windowEndAt));
    if (eligible.length >= 2 &&
        eligible.take(2).every((a) => a.state.breaksStreak)) {
      return _step(commitment, up: false);
    }
    final lastSeven = eligible.take(7).toList();
    if (lastSeven.length == 7 &&
        lastSeven.where((a) => a.state == AttemptState.completed).length >= 6) {
      return _step(commitment, up: true);
    }
    return null;
  }

  static LadderOffer? _step(Commitment c, {required bool up}) {
    final sign = up ? 1 : -1;
    int bump(int value, int step, int lo, int hi) =>
        min(hi, max(lo, value + sign * step));
    VerifierConfig? next;
    var change = '';
    switch (c.verifierConfig) {
      case WalkConfig(mode: WalkGoalMode.duration) && final cfg:
        final minutes = bump(cfg.targetDurationMs ~/ 60000, 5, 5, 120);
        next = WalkConfig(
          mode: cfg.mode,
          targetDurationMs: minutes * 60000,
          targetDistanceM: cfg.targetDistanceM,
        );
        change = '$minutes minutes';
      case WalkConfig(mode: WalkGoalMode.distance) && final cfg:
        final metres = bump(cfg.targetDistanceM, 500, 500, 20000);
        next = WalkConfig(
          mode: cfg.mode,
          targetDurationMs: cfg.targetDurationMs,
          targetDistanceM: metres,
        );
        change = '${(metres / 1000).toStringAsFixed(1)} km';
      case FocusConfig() && final cfg:
        final minutes = bump(cfg.targetDurationMs ~/ 60000, 5, 5, 180);
        next = FocusConfig(
          packages: cfg.packages,
          targetDurationMs: minutes * 60000,
          graceSeconds: cfg.graceSeconds,
        );
        change = '$minutes minutes';
      case LeetCodeConfig() && final cfg:
        final count = bump(cfg.targetAccepted, 1, 1, 10);
        next = LeetCodeConfig(
          username: cfg.username,
          targetAccepted: count,
          ownerVerifiedAtMs: cfg.ownerVerifiedAtMs,
        );
        change = '$count problem${count == 1 ? '' : 's'}';
      case StepsConfig() && final cfg:
        final steps = bump(cfg.targetSteps, 500, 500, 20000);
        next = StepsConfig(
          targetSteps: steps,
          minDurationMs: cfg.minDurationMs,
        );
        change = '$steps steps';
      default:
      // Places, destinations, tags and workouts have no sensible step.
    }
    if (next == null ||
        jsonEncode(next.toJson()) == jsonEncode(c.verifierConfig.toJson())) {
      return null;
    }
    return LadderOffer(
      commitmentId: c.id,
      up: up,
      config: next,
      title: defaultTitle(c.kind, next),
      change: change,
    );
  }
}
