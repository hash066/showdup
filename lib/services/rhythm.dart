import '../models/attempt.dart';
import '../models/enums.dart';

/// Share of finished windows you showed up for. Windows your phone could not
/// check are left out, so a sensor problem never lowers it.
class Rhythm {
  const Rhythm({required this.kept, required this.counted});

  final int kept;
  final int counted;

  int? get percent => counted == 0 ? null : (kept * 100 / counted).round();

  static Rhythm of(Iterable<Attempt> attempts, DateTime now, {int days = 28}) {
    final since = now.subtract(Duration(days: days));
    var kept = 0;
    var counted = 0;
    for (final attempt in attempts) {
      if (!attempt.state.isTerminal ||
          attempt.state == AttemptState.unverifiable ||
          attempt.windowEndAt.isBefore(since)) {
        continue;
      }
      counted++;
      if (attempt.state == AttemptState.completed) kept++;
    }
    return Rhythm(kept: kept, counted: counted);
  }
}
