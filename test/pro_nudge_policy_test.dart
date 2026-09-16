import 'package:flutter_test/flutter_test.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/services/pro_nudge_policy.dart';

Attempt attempt({
  String id = 'a',
  AttemptState state = AttemptState.completed,
  int snoozes = 0,
  int focusResets = 0,
}) => Attempt(
  id: id,
  commitmentId: 'c',
  ownerUid: 'u',
  date: '2026-09-16',
  windowStartAt: DateTime(2026, 9, 16, 7),
  windowEndAt: DateTime(2026, 9, 16, 8),
  state: state,
  snoozes: snoozes,
  evidence: focusResets == 0 ? null : {'resetCount': focusResets},
);

void main() {
  test('Pro users and low-friction users are never prompted', () {
    expect(ProNudgePolicy.next([attempt()], isPro: false), isNull);
    expect(ProNudgePolicy.next([attempt(snoozes: 20)], isPro: true), isNull);
  });

  test('focus milestones take priority and use stable fifty-step keys', () {
    final moment = ProNudgePolicy.next([
      attempt(id: 'a', focusResets: 49),
      attempt(id: 'b', focusResets: 52),
    ], isPro: false);
    expect(moment?.key, 'focus:100');
    expect(moment?.title, contains('100'));
  });

  test('snoozes and genuine misses create contextual milestones', () {
    expect(
      ProNudgePolicy.next([attempt(snoozes: 7)], isPro: false)?.key,
      'snooze:5',
    );
    expect(
      ProNudgePolicy.next([
        attempt(id: 'a', state: AttemptState.expired),
        attempt(id: 'b', state: AttemptState.abandoned),
        attempt(id: 'c', state: AttemptState.expired),
        attempt(id: 'd', state: AttemptState.unverifiable),
      ], isPro: false)?.key,
      'miss:3',
    );
  });
}
