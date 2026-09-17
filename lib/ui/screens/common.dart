import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../design/motion.dart';
import '../../design/buttons.dart';
import '../../design/chrome.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/mark.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../models/attempt.dart';
import '../../models/commitment.dart';
import '../../models/enums.dart';
import '../../models/verifier_config.dart';
import '../../platform/alarm_channel.dart';
import '../../services/billing.dart';
import '../../services/controller.dart';
import '../../services/repository.dart' show proProofMessage;
import '../wizard.dart';
import 'attempt.dart';
import 'pro.dart';

void openWizard(BuildContext context, {Commitment? commitment}) =>
    Navigator.push(
      context,
      ShowdRoute<void>(builder: (_) => CommitmentWizard(existing: commitment)),
    );

void openAttempt(BuildContext context, Attempt attempt) => Navigator.push(
  context,
  ShowdRoute<void>(builder: (_) => AttemptScreen(attemptId: attempt.id)),
);

/// Opens the store paywall, or the in-app plan page when RevenueCat is not
/// configured (previews, tests, sideloaded builds).
Future<void> openPro(BuildContext context) async {
  String? problem;
  if (Billing.initialized) {
    try {
      await Billing.paywall();
      return;
    } catch (error) {
      problem = friendlyError(error);
    }
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    ShowdRoute<void>(builder: (_) => ProScreen(initialMessage: problem)),
  );
}

/// The phone's own alarm, set in its Clock app. Rings once.
Future<void> showRegularAlarmSheet(BuildContext context) =>
    showShowdSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: ShowdMark(state: MarkState.ringing, size: 64)),
          const SizedBox(height: ShowdSpace.s4),
          Center(child: Text('Regular alarm', style: ShowdType.titleL)),
          const SizedBox(height: ShowdSpace.s1),
          Center(
            child: Text(
              'Rings once, in your Clock app.',
              style: ShowdType.bodyM,
            ),
          ),
          const SizedBox(height: ShowdSpace.s6),
          ShowdButton(
            label: 'Set a time',
            icon: ShowdIcons.alarm,
            onPressed: () async {
              final time = await showTimePicker(
                context: sheetContext,
                initialTime: const TimeOfDay(hour: 7, minute: 0),
              );
              if (time == null || !sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              try {
                await AlarmChannel.createNativeAlarm(
                  hour: time.hour,
                  minute: time.minute,
                  label: 'ShowdUp',
                );
              } catch (error) {
                if (context.mounted) showMessage(context, friendlyError(error));
              }
            },
          ),
          const SizedBox(height: ShowdSpace.s2),
          ShowdButton(
            label: 'Open Clock',
            tone: ShowdButtonTone.quiet,
            onPressed: () async {
              Navigator.pop(sheetContext);
              try {
                await AlarmChannel.showNativeAlarms();
              } catch (error) {
                if (context.mounted) showMessage(context, friendlyError(error));
              }
            },
          ),
        ],
      ),
    );

/// A quiet upgrade prompt: one line of why, one action.
Future<void> showProSheet(
  BuildContext context, {
  required String title,
  required String body,
}) => showShowdSheet<void>(
  context,
  builder: (sheetContext) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ProPill(),
      const SizedBox(height: ShowdSpace.s3),
      Text(title, style: ShowdType.titleL),
      const SizedBox(height: ShowdSpace.s2),
      Text(body, style: ShowdType.bodyM),
      const SizedBox(height: ShowdSpace.s6),
      ShowdButton(
        label: 'See Pro',
        onPressed: () {
          Navigator.pop(sheetContext);
          openPro(context);
        },
      ),
      const SizedBox(height: ShowdSpace.s2),
      ShowdButton(
        label: 'Not now',
        tone: ShowdButtonTone.quiet,
        onPressed: () => Navigator.pop(sheetContext),
      ),
    ],
  ),
);

/// Shows a repository limit error as an upgrade sheet when it is the free
/// tier talking, otherwise as a plain message.
Future<void> showLimitOrMessage(BuildContext context, Object error) {
  final message = friendlyError(error);
  if (message == proProofMessage) {
    return showProSheet(
      context,
      title: 'Gym, places and GPS walks are Pro.',
      body:
          'They check you in automatically when you get there. Steps, phone-down focus, tag scans and LeetCode stay free.',
    );
  }
  if (message.startsWith('Free')) {
    return showProSheet(
      context,
      title: 'Free keeps one proof alarm on.',
      body:
          'Pause the one you have, or get Pro for up to 20 running side by side.',
    );
  }
  return showMessage(context, message);
}

Future<void> showMessage(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

/// Mark for an attempt, including rest days.
MarkState attemptMark(Attempt attempt) =>
    attempt.restCovered ? MarkState.rest : markStateFor(attempt.state);

String attemptLabel(Attempt attempt) =>
    attempt.restCovered ? 'Rest day' : stateLabel(attempt.state);

String stateLabel(AttemptState state) => switch (state) {
  AttemptState.pending => 'Open',
  AttemptState.completed => 'Showed up',
  AttemptState.abandoned => 'Ended',
  AttemptState.expired => 'Missed',
  AttemptState.unverifiable => 'Couldn’t tell',
};

MarkState markStateFor(AttemptState state) => switch (state) {
  AttemptState.pending => MarkState.ringing,
  AttemptState.completed => MarkState.showedUp,
  AttemptState.abandoned || AttemptState.expired => MarkState.missed,
  AttemptState.unverifiable => MarkState.unverifiable,
};

ShowdIcons kindIcon(CommitmentKind kind) => switch (kind) {
  CommitmentKind.walk => ShowdIcons.walk,
  CommitmentKind.gym => ShowdIcons.gym,
  CommitmentKind.arrive => ShowdIcons.arrive,
  CommitmentKind.focus => ShowdIcons.focus,
  CommitmentKind.workout => ShowdIcons.gym,
  CommitmentKind.leetcode => ShowdIcons.code,
  CommitmentKind.steps => ShowdIcons.steps,
  CommitmentKind.tagScan => ShowdIcons.tagScan,
};

String kindLabel(CommitmentKind kind) => switch (kind) {
  CommitmentKind.walk => 'Walk or run',
  CommitmentKind.gym => 'Gym',
  CommitmentKind.arrive => 'Arrive somewhere',
  CommitmentKind.focus => 'Phone-down focus',
  CommitmentKind.workout => 'Workout',
  CommitmentKind.leetcode => 'LeetCode',
  CommitmentKind.steps => 'Steps',
  CommitmentKind.tagScan => 'Tag scan',
};

String hhmm(DateTime value) => DateFormat('HH:mm').format(value.toLocal());

/// Clock time in the alarm's own timezone, which is what the person set.
String zoneClock(DateTime instant, String timezone) {
  try {
    return DateFormat(
      'HH:mm',
    ).format(tz.TZDateTime.from(instant, tz.getLocation(timezone)));
  } catch (_) {
    return hhmm(instant);
  }
}

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String daysLabel(List<int> days) {
  final sorted = [...days]..sort();
  if (sorted.length == 7) return 'Every day';
  if (sorted.join() == '12345') return 'Weekdays';
  if (sorted.join() == '67') return 'Weekends';
  return sorted.map((d) => weekdayShort[d - 1]).join(', ');
}

String scheduleLine(Commitment c) => c.schedule.hasCustomWindows
    ? '${daysLabel(c.schedule.daysOfWeek)} · own time each day'
    : '${daysLabel(c.schedule.daysOfWeek)} · ${c.schedule.windowStartLocal}–${c.schedule.windowEndLocal}';

String goalDescription(Commitment c) {
  final cfg = c.verifierConfig;
  return switch (cfg) {
    StepsConfig(:final targetSteps) =>
      '${NumberFormat.decimalPattern().format(targetSteps)} new steps in the window',
    WalkConfig(mode: WalkGoalMode.duration, :final targetDurationMs) =>
      '${targetDurationMs ~/ 60000} minutes on the move',
    WalkConfig(mode: WalkGoalMode.distance, :final targetDistanceM) =>
      '${_km(targetDistanceM)} km by GPS',
    WalkConfig(:final label) =>
      'Walk to ${label?.isNotEmpty == true ? label : 'your destination'}',
    LocationConfig(:final label, :final dwellMs) =>
      'Stay at ${label?.isNotEmpty == true ? label : 'your place'} for ${dwellMs ~/ 60000} minutes',
    FocusConfig(:final targetDurationMs, :final packages) =>
      '${targetDurationMs ~/ 60000} minutes away from ${packages.length} app${packages.length == 1 ? '' : 's'}',
    HealthWorkoutConfig(:final targetDurationMs) =>
      '${targetDurationMs ~/ 60000} recorded workout minutes',
    LeetCodeConfig(:final targetAccepted, :final username) =>
      '$targetAccepted accepted problem${targetAccepted == 1 ? '' : 's'} on @$username',
    TagScanConfig(:final label) =>
      'Scan your tag${label?.isNotEmpty == true ? ' at $label' : ''}',
  };
}

String proofDescription(Commitment c) => switch (c.verifierConfig) {
  WalkConfig() =>
    'GPS on this phone counts real movement. Fake, stale and blurry locations are ignored. It proves the phone moved with you, not how hard you worked.',
  LocationConfig(:final dwellMs, :final radiusM) =>
    'GPS checks that you stay within $radiusM m of the place for ${dwellMs ~/ 60000} minutes in a row.',
  FocusConfig() =>
    'Android tells ShowdUp only which app is in front. Ten seconds in one of your chosen apps restarts the timer.',
  HealthWorkoutConfig() =>
    'One workout recorded by a sensor in Health Connect must reach the time. Typed-in entries never count.',
  LeetCodeConfig() =>
    'New accepted problems on your public LeetCode profile count if they land inside the window.',
  StepsConfig() =>
    'Android’s step counter must record new steps during the window, at a pace a person can walk.',
  TagScanConfig() =>
    'Scan the same code you set up. Google’s scanner reads it on the phone, and only a scrambled fingerprint is compared.',
};

/// The one number on the proof screen, with its unit line.
({String value, String unit}) proofNumber(Commitment c, double progress) {
  final p = progress.clamp(0.0, 1.0);
  return switch (c.verifierConfig) {
    StepsConfig(:final targetSteps) => (
      value: NumberFormat.decimalPattern().format((p * targetSteps).round()),
      unit: 'of ${NumberFormat.decimalPattern().format(targetSteps)} steps',
    ),
    WalkConfig(mode: WalkGoalMode.duration, :final targetDurationMs) => (
      value: '${(p * targetDurationMs / 60000).floor()}',
      unit: 'of ${targetDurationMs ~/ 60000} minutes',
    ),
    WalkConfig(mode: WalkGoalMode.distance, :final targetDistanceM) => (
      value: _km((p * targetDistanceM).round()),
      unit: 'of ${_km(targetDistanceM)} km',
    ),
    WalkConfig() => (value: '${(p * 100).round()}%', unit: 'of the way there'),
    LocationConfig(:final dwellMs) => (
      value: '${(p * dwellMs / 60000).floor()}',
      unit: 'of ${dwellMs ~/ 60000} minutes there',
    ),
    FocusConfig(:final targetDurationMs) ||
    HealthWorkoutConfig(:final targetDurationMs) => (
      value: '${(p * targetDurationMs / 60000).floor()}',
      unit: 'of ${targetDurationMs ~/ 60000} minutes',
    ),
    LeetCodeConfig(:final targetAccepted) => (
      value: '${(p * targetAccepted).floor()}',
      unit: 'of $targetAccepted accepted',
    ),
    TagScanConfig(:final label) => (
      value: p >= 1 ? 'Scanned' : 'Scan',
      unit: label?.isNotEmpty == true ? 'at $label' : 'your tag',
    ),
  };
}

String _km(int metres) {
  final km = metres / 1000;
  return km == km.roundToDouble()
      ? km.toStringAsFixed(0)
      : km.toStringAsFixed(1);
}

/// One attempt as a plain row: mark, title, date, state.
class AttemptRow extends StatelessWidget {
  const AttemptRow(this.attempt, this.title, {super.key});
  final Attempt attempt;
  final String title;

  @override
  Widget build(BuildContext context) => ShowdRow(
    onTap: () => openAttempt(context, attempt),
    leading: ShowdMark(state: attemptMark(attempt), size: 32),
    title: title,
    subtitle: DateFormat('EEE d MMM').format(DateTime.parse(attempt.date)),
    trailing: Text(
      attemptLabel(attempt),
      style: ShowdType.bodyM.copyWith(
        color: attempt.state == AttemptState.completed
            ? ShowdColors.accent
            : ShowdColors.stone,
      ),
    ),
  );
}

/// Heading used at the top of pushed screens: back, title, optional action.
class PushedHeader extends StatelessWidget {
  const PushedHeader({
    super.key,
    this.title,
    this.trailing,
    this.close = false,
    this.onBack,
  });
  final String? title;
  final Widget? trailing;
  final bool close;

  /// Defaults to popping the current route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ScreenHeader(
      leading: ShowdIconButton(
        icon: close ? ShowdIcons.close : ShowdIcons.back,
        semanticLabel: close ? 'Close' : 'Back',
        onPressed: onBack ?? () => Navigator.maybePop(context),
      ),
      title: title,
      trailing: trailing,
    ),
  );
}
