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

/// Turns local proof into contextual upgrade moments without uploading or
/// inspecting screen content. Each key is stable so it is shown only once.
class ProNudgePolicy {
  const ProNudgePolicy._();

  static ProNudgeMoment? next(
    Iterable<Attempt> attempts, {
    required bool isPro,
  }) {
    if (isPro) return null;
    final values = attempts.toList();
    final focusResets = values.fold<int>(
      0,
      (sum, attempt) =>
          sum + ((attempt.evidence?['resetCount'] as num?)?.toInt() ?? 0),
    );
    final resetMilestone = (focusResets ~/ 50) * 50;
    if (resetMilestone >= 50) {
      return ProNudgeMoment(
        key: 'focus:$resetMilestone',
        title: '$resetMilestone distraction attempts noticed.',
        body:
            'ShowdUp kept the proof local. Pro can turn those interruptions into an immediate block during your commitment window.',
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
        title: '$snoozeMilestone snoozes are a pattern.',
        body:
            'Pro can block your selected escape apps while the promise is active, so the next alarm has less work to do.',
      );
    }

    final misses = values
        .where(
          (attempt) =>
              attempt.state == AttemptState.expired ||
              attempt.state == AttemptState.abandoned,
        )
        .length;
    final missMilestone = (misses ~/ 3) * 3;
    if (missMilestone >= 3) {
      return ProNudgeMoment(
        key: 'miss:$missMilestone',
        title: 'Your last $missMilestone misses left a clue.',
        body:
            'Add active blocking and more commitment windows with Pro. Your evidence and app activity still stay on this phone.',
      );
    }
    return null;
  }
}
