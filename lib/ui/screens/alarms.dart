import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/features.dart';
import '../../core/scheduling.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/mark.dart';
import '../../design/motion.dart';
import '../../design/sensory.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../models/attempt.dart';
import '../../models/commitment.dart';
import '../../models/enums.dart';
import '../../models/verifier_config.dart';
import '../../services/controller.dart';
import '../../services/pro_nudge_policy.dart';
import '../app_provider.dart';
import '../keys.dart';
import 'common.dart';

/// Home tab. The mark is the face: it rings, shows up, rests. Under it, the
/// time, the name and one button.
class AlarmsScreen extends ConsumerWidget {
  const AlarmsScreen({
    super.key,
    this.nudge,
    this.onNudgeOpen,
    this.onNudgeDismiss,
  });

  final ProNudgeMoment? nudge;
  final VoidCallback? onNudgeOpen;
  final VoidCallback? onNudgeDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final now = DateTime.now();
    final today = _todayAttempts(app.attempts, now);
    final active = app.commitments
        .where((c) => c.status == CommitmentStatus.active)
        .toList();
    final drafts = app.commitments
        .where((c) => c.status == CommitmentStatus.draft)
        .toList();
    final a = today.firstOrNull;
    final c = a == null ? null : app.commitment(a.commitmentId);
    final rest = restOfToday(today, a?.commitmentId);
    final offers = [
      for (final commitment in active)
        if (app.ladderOffer(commitment.id) case final offer?
            when !offer.up &&
                !app.attempts.any(
                  (x) =>
                      x.commitmentId == commitment.id &&
                      x.state == AttemptState.pending,
                ))
          (commitment, offer),
    ];
    return RefreshIndicator(
      color: ShowdColors.accent,
      backgroundColor: ShowdColors.carbon,
      onRefresh: () async {
        Sensory.play(Cue.page);
        await app.refresh();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        child: app.loading
            ? const _HeroSkeleton(key: ValueKey('loading'))
            : ListView(
                key: const ValueKey('ready'),
                padding: const EdgeInsets.fromLTRB(
                  ShowdSpace.gutter,
                  ShowdSpace.s2,
                  ShowdSpace.gutter,
                  ShowdSpace.s8,
                ),
                children: [
                  if (app.error != null)
                    ShowdNotice(app.error!, onRetry: app.refresh),
                  if (a != null && c != null)
                    _Hero(app: app, attempt: a, commitment: c)
                  else
                    _Empty(active: active, drafts: drafts, now: now),
                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: ShowdSpace.s8),
                    ...staggered([
                      for (final other in rest)
                        AttemptRow(
                          other,
                          app.commitment(other.commitmentId)?.title ?? 'Alarm',
                        ),
                    ], start: const Duration(milliseconds: 360)),
                  ],
                  for (final (commitment, offer) in offers) ...[
                    const SizedBox(height: ShowdSpace.s6),
                    Reveal(
                      delay: const Duration(milliseconds: 420),
                      child: _Card(
                        icon: ShowdIcons.next,
                        title: 'Try ${offer.change}?',
                        body: 'Two misses in a row. Smaller wins count.',
                        action: 'Make it smaller',
                        onAction: () async {
                          try {
                            await app.acceptLadder(offer);
                            Sensory.play(Cue.toggleOn);
                          } catch (e) {
                            if (context.mounted) {
                              showMessage(context, friendlyError(e));
                            }
                          }
                        },
                        onDismiss: () => app.dismissLadder(commitment.id),
                      ),
                    ),
                  ],
                  if (nudge != null) ...[
                    const SizedBox(height: ShowdSpace.s6),
                    Reveal(
                      delay: const Duration(milliseconds: 480),
                      child: _Card(
                        icon: ShowdIcons.caught,
                        title: nudge!.title,
                        body: nudge!.body,
                        action: 'See Pro',
                        onAction: onNudgeOpen,
                        onDismiss: onNudgeDismiss,
                      ),
                    ),
                  ],
                  if (Features.restDays &&
                      app.restBanked != null &&
                      active.isNotEmpty) ...[
                    const SizedBox(height: ShowdSpace.s6),
                    Reveal(
                      delay: const Duration(milliseconds: 520),
                      child: _RestButton(app: app),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// The rows under the hero: one per other alarm. Tomorrow's attempt for the
  /// alarm already in the hero is the same alarm, so it never gets its own row.
  static List<Attempt> restOfToday(List<Attempt> today, String? heroCommitment) {
    final rest = <Attempt>[];
    for (final other in today.skip(1)) {
      if (other.commitmentId == heroCommitment) continue;
      if (rest.any((x) => x.commitmentId == other.commitmentId)) continue;
      rest.add(other);
    }
    return rest;
  }

  static List<Attempt> _todayAttempts(List<Attempt> attempts, DateTime now) {
    int rank(Attempt attempt) {
      if (attempt.state == AttemptState.pending && attempt.isWindowOpen) {
        return 0;
      }
      if (attempt.state == AttemptState.pending) return 1;
      return 2;
    }

    return attempts
        .where(
          (a) =>
              a.windowEndAt.isAfter(now.subtract(const Duration(hours: 6))) &&
              a.windowStartAt.isBefore(now.add(const Duration(hours: 24))),
        )
        .toList()
      ..sort((left, right) {
        final byRank = rank(left).compareTo(rank(right));
        if (byRank != 0) return byRank;
        return left.windowStartAt.compareTo(right.windowStartAt);
      });
  }
}

/// A short tag: an icon and two or three words.
class InfoTag extends StatelessWidget {
  const InfoTag(this.icon, this.label, {super.key, this.accent = false});
  final ShowdIcons icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
    decoration: BoxDecoration(
      color: accent
          ? ShowdColors.accent.withValues(alpha: .12)
          : ShowdColors.carbon,
      borderRadius: BorderRadius.circular(ShowdRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShowdIcon(
          icon,
          size: 16,
          color: accent ? ShowdColors.accent : ShowdColors.stone,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: ShowdType.bodyM.copyWith(
            color: accent ? ShowdColors.accent : ShowdColors.paper,
          ),
        ),
      ],
    ),
  );
}

/// The goal in a few characters, like "3,000" or "25 min".
(ShowdIcons, String) goalTag(Commitment c) => switch (c.verifierConfig) {
  StepsConfig(:final targetSteps) => (
    ShowdIcons.steps,
    NumberFormat.decimalPattern().format(targetSteps),
  ),
  WalkConfig(mode: WalkGoalMode.distance, :final targetDistanceM) => (
    ShowdIcons.walk,
    '${(targetDistanceM / 1000).toStringAsFixed(1)} km',
  ),
  WalkConfig(:final targetDurationMs, :final mode) => (
    ShowdIcons.walk,
    mode == WalkGoalMode.duration
        ? '${targetDurationMs ~/ 60000} min'
        : 'Walk there',
  ),
  LocationConfig(:final label) => (
    kindIcon(c.kind),
    label?.isNotEmpty == true ? label! : 'Arrive',
  ),
  FocusConfig(:final targetDurationMs) => (
    ShowdIcons.focus,
    '${targetDurationMs ~/ 60000} min',
  ),
  HealthWorkoutConfig(:final targetDurationMs) => (
    ShowdIcons.gym,
    '${targetDurationMs ~/ 60000} min',
  ),
  LeetCodeConfig(:final targetAccepted) => (ShowdIcons.code, '$targetAccepted'),
  TagScanConfig(:final label) => (
    ShowdIcons.tagScan,
    label?.isNotEmpty == true ? label! : 'Scan',
  ),
};

class _Hero extends StatelessWidget {
  const _Hero({
    required this.app,
    required this.attempt,
    required this.commitment,
  });

  final AppController app;
  final Attempt attempt;
  final Commitment commitment;

  @override
  Widget build(BuildContext context) {
    final a = attempt;
    final open = a.state == AttemptState.pending && a.isWindowOpen;
    final progress = app.progress[a.id] ?? (app.preview && open ? .64 : 0.0);
    final zone = commitment.schedule.timezone;
    final opens = zoneClock(a.windowStartAt, zone);
    final today = DateUtils.isSameDay(
      a.windowStartAt.toLocal(),
      DateTime.now(),
    );
    final (MarkState mark, String status) = switch (a.state) {
      AttemptState.pending when open => (MarkState.ringing, 'Now'),
      AttemptState.pending => (
        MarkState.ringing,
        today ? 'Today' : DateFormat('EEE').format(a.windowStartAt.toLocal()),
      ),
      _ when a.restCovered => (MarkState.rest, 'Rest day'),
      AttemptState.completed => (MarkState.showedUp, 'Showed up'),
      AttemptState.abandoned => (MarkState.missed, 'Ended'),
      AttemptState.expired => (MarkState.missed, 'Missed'),
      AttemptState.unverifiable => (MarkState.unverifiable, 'Couldn’t tell'),
    };
    final (goalIcon, goal) = goalTag(commitment);
    return Column(
      children: staggered([
        Padding(
          padding: const EdgeInsets.only(top: ShowdSpace.s6),
          child: Center(
            child: mark == MarkState.showedUp
                ? Breathe(child: ShowdMark(state: mark, size: 140))
                : RingingMark(size: 140, state: mark, ringing: open),
          ),
        ),
        const SizedBox(height: ShowdSpace.s6),
        BigNumber(
          opens,
          align: Alignment.center,
          color: open ? ShowdColors.accent : ShowdColors.paper,
          semanticLabel: 'Alarm at $opens',
        ),
        Text(
          commitment.title,
          textAlign: TextAlign.center,
          style: ShowdType.titleL,
        ),
        const SizedBox(height: ShowdSpace.s3),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: ShowdSpace.s2,
          runSpacing: ShowdSpace.s2,
          children: [
            InfoTag(
              ShowdIcons.alarm,
              open
                  ? '$status · till ${zoneClock(a.windowEndAt, zone)}'
                  : status,
              accent: open,
            ),
            InfoTag(goalIcon, goal),
          ],
        ),
        if (open) ...[
          const SizedBox(height: ShowdSpace.s6),
          ProofBar(progress: progress),
        ],
        const SizedBox(height: ShowdSpace.s6),
        ShowdButton(
          label: a.state.isTerminal
              ? 'See today'
              : open
              ? (app.progress.containsKey(a.id) ? 'Keep going' : 'Prove it')
              : 'See the plan',
          icon: open ? ShowdIcons.check : null,
          onPressed: () => openAttempt(context, a),
        ),
      ], step: const Duration(milliseconds: 60)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.active, required this.drafts, required this.now});

  final List<Commitment> active;
  final List<Commitment> drafts;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (title, tag, action, onPressed) = active.isNotEmpty
        ? (
            'Quiet today.',
            DateFormat(
              'EEE d · HH:mm',
            ).format(nextWindow(active.first.schedule, now).toLocal()),
            'See the alarm',
            () => openWizard(context, commitment: active.first),
          )
        : drafts.isNotEmpty
        ? (
            'One step left.',
            drafts.first.title,
            'Finish setup',
            () => openWizard(context, commitment: drafts.first),
          )
        : (
            'No alarm yet.',
            null,
            'Set my first alarm',
            () => openWizard(context),
          );
    return Column(
      children: staggered([
        const SizedBox(height: ShowdSpace.s12),
        Center(
          child: active.isNotEmpty
              ? const Breathe(
                  child: ShowdMark(state: MarkState.rest, size: 140),
                )
              : const RingingMark(size: 140),
        ),
        const SizedBox(height: ShowdSpace.s8),
        Text(title, textAlign: TextAlign.center, style: ShowdType.hero),
        if (tag != null) ...[
          const SizedBox(height: ShowdSpace.s3),
          Center(child: InfoTag(ShowdIcons.alarm, tag)),
        ],
        const SizedBox(height: ShowdSpace.s8),
        ShowdButton(
          key: active.isEmpty && drafts.isEmpty
              ? ShowdKeys.createFirstCommitment
              : null,
          label: action,
          icon: active.isEmpty && drafts.isEmpty ? ShowdIcons.add : null,
          onPressed: onPressed,
        ),
      ]),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(ShowdSpace.gutter),
    physics: const NeverScrollableScrollPhysics(),
    children: const [
      SizedBox(height: ShowdSpace.s4),
      Center(child: ShowdLoader(size: 88)),
      SizedBox(height: ShowdSpace.s8),
      Shimmer(
        child: Column(
          children: [
            SkeletonBox(width: 220, height: 96, radius: 18),
            SizedBox(height: ShowdSpace.s4),
            SkeletonBox(width: 180, height: 24, radius: 12),
            SizedBox(height: ShowdSpace.s3),
            SkeletonBox(width: 140, height: 28, radius: 14),
            SizedBox(height: ShowdSpace.s8),
            SkeletonBox(height: 56),
          ],
        ),
      ),
    ],
  );
}

class _RestButton extends StatelessWidget {
  const _RestButton({required this.app});
  final AppController app;

  Future<void> _rest(BuildContext context) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final planned = await app.planRest(
      DateFormat('yyyy-MM-dd').format(tomorrow),
    );
    if (context.mounted) {
      Sensory.play(planned ? Cue.land : Cue.error);
      showMessage(
        context,
        planned ? 'Rest day tomorrow. Rhythm kept.' : 'No rest days saved yet.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final banked = app.restBanked ?? 0;
    return ShowdButton(
      label: banked > 0
          ? 'Rest tomorrow · $banked saved'
          : 'Rest days: show up 5 times',
      icon: ShowdIcons.rest,
      tone: ShowdButtonTone.outline,
      onPressed: banked > 0 ? () => _rest(context) : null,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    required this.onDismiss,
  });

  final ShowdIcons icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
    decoration: BoxDecoration(
      color: ShowdColors.carbon,
      borderRadius: BorderRadius.circular(ShowdRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShowdIcon(icon, color: ShowdColors.accent),
            const SizedBox(width: ShowdSpace.s3),
            Expanded(child: Text(title, style: ShowdType.titleM)),
            ShowdIconButton(
              icon: ShowdIcons.close,
              semanticLabel: 'Dismiss',
              color: ShowdColors.stone,
              onPressed: onDismiss,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 36, right: 12),
          child: Text(body, style: ShowdType.bodyM),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: TextButton(
            onPressed: onAction == null
                ? null
                : () {
                    Sensory.play(Cue.tap);
                    onAction!();
                  },
            child: Text(action),
          ),
        ),
      ],
    ),
  );
}
