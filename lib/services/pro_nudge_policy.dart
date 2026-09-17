import '../models/attempt.dart';
import '../models/enums.dart';

class ProNudgeMoment {
  const ProNudgeMoment({
    required this.key,
    required this.title,
    required this.body,
  });

  final String key;
  final String title;
  final String body;
}

/// Turns local proof into quiet upgrade moments around catches, snoozes and
/// misses. Nothing is uploaded. Each key is stable so it shows only once.
class ProNudgePolicy {
  const ProNudgePolicy._();

  static ProNudgeMoment? next(
    Iterable<Attempt> attempts, {
    required bool isPro,
    int reaches = 0,
  }) {
    if (isPro) return null;
    final values = attempts.toList();

    final reachMilestone = (reaches ~/ 10) * 10;
    if (reachMilestone >= 10) {
      return ProNudgeMoment(
        key: 'reach:$reachMilestone',
        title: 'You reached for it $reachMilestone times.',
        body:
            'And still showed up. Pro can hold every app you reach for, on every alarm.',
      );
    }

    final focusResets = values.fold<int>(
      0,
      (sum, attempt) =>
          sum + ((attempt.evidence?['resetCount'] as num?)?.toInt() ?? 0),
    );
    final resetMilestone = (focusResets ~/ 50) * 50;
    if (resetMilestone >= 50) {
      return ProNudgeMoment(
        key: 'focus:$resetMilestone',
        title: '$resetMilestone times an app pulled you away.',
        body:
            'Pro can keep those apps closed until the timer is done, instead of restarting it.',
      );
    }

    final snoozes = values.fold<int>(
      0,
      (sum, attempt) => sum + attempt.snoozes,
    );
    final snoozeMilestone = (snoozes ~/ 5) * 5;
    if (snoozeMilestone >= 5) {
      return ProNudgeMoment(
        key: 'snooze:$snoozeMilestone',
        title: '$snoozeMilestone snoozes. That’s a pattern.',
        body:
            'Holding the app you escape into makes the next snooze less tempting. Pro holds more than one.',
      );
    }

    final misses = values
        .where(
          (attempt) =>
              !attempt.restCovered &&
              (attempt.state == AttemptState.expired ||
                  attempt.state == AttemptState.abandoned),
        )
        .length;
    final missMilestone = (misses ~/ 3) * 3;
    if (missMilestone >= 3) {
      return ProNudgeMoment(
        key: 'miss:$missMilestone',
        title: '$missMilestone misses left a clue.',
        body:
            'Often the time or the place is the problem. Pro adds gym check-ins and a different time each day.',
      );
    }
    return null;
  }
}
