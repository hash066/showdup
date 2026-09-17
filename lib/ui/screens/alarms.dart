import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/scheduling.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/mark.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../models/attempt.dart';
import '../../models/commitment.dart';
import '../../models/enums.dart';
import '../../platform/alarm_channel.dart';
import '../../core/features.dart';
import '../../services/controller.dart';
import '../../services/pro_nudge_policy.dart';
import '../app_provider.dart';
import '../keys.dart';
import 'common.dart';

/// Home tab. One hero number (the alarm time), the promise and one action.
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
    final stats = app.user?.stats;
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ShowdSpace.gutter,
          ShowdSpace.s4,
          ShowdSpace.gutter,
          ShowdSpace.s8,
        ),
        children: [
          if (app.error != null) ShowdNotice(app.error!, onRetry: app.refresh),
          if (app.loading)
            const Padding(
              padding: EdgeInsets.all(ShowdSpace.s12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (a != null && c != null)
            _Hero(app: app, attempt: a, commitment: c)
          else
            _Empty(active: active, drafts: drafts, now: now),
          if (today.length > 1) ...[
            const SizedBox(height: ShowdSpace.s8),
            const SectionLabel('Also today'),
            const SizedBox(height: ShowdSpace.s2),
            for (final other in today.skip(1))
              AttemptRow(
                other,
                app.commitment(other.commitmentId)?.title ?? 'Alarm',
              ),
          ],
          for (final commitment in active)
            if (app.ladderOffer(commitment.id) case final offer?
                when !offer.up &&
                    !app.attempts.any(
                      (x) =>
                          x.commitmentId == commitment.id &&
                          x.state == AttemptState.pending,
                    )) ...[
              const SizedBox(height: ShowdSpace.s8),
              _Offer(
                title: 'Two misses in a row.',
                body:
                    'Smaller wins count. Try ${offer.change} for ${commitment.title.toLowerCase()} for a while?',
                action: 'Make it ${offer.change}',
                onAction: () async {
                  try {
                    await app.acceptLadder(offer);
                  } catch (e) {
                    if (context.mounted) {
                      showMessage(context, friendlyError(e));
                    }
                  }
                },
                onDismiss: () => app.dismissLadder(commitment.id),
              ),
            ],
          if (nudge != null) ...[
            const SizedBox(height: ShowdSpace.s8),
            _NudgeCard(
              moment: nudge!,
              onOpen: onNudgeOpen,
              onDismiss: onNudgeDismiss,
            ),
          ],
          const SizedBox(height: ShowdSpace.s8),
          if (Features.restDays && app.restBanked != null && active.isNotEmpty)
            ShowdRow(
              leading: const ShowdIcon(ShowdIcons.rest),
              title: 'Rest tomorrow',
              subtitle: app.restBanked! > 0
                  ? 'Uses 1 of ${app.restBanked} saved. Tomorrow’s alarms stay quiet.'
                  : 'Show up 5 times to save a rest day.',
              onTap: app.restBanked! > 0
                  ? () => _restTomorrow(context, app)
                  : null,
            ),
          ShowdRow(
            leading: const ShowdIcon(ShowdIcons.alarm),
            title: 'Regular alarm',
            subtitle: 'Rings once. Set in your Clock app.',
            onTap: () => _regularAlarm(context),
            trailing: TextButton(
              onPressed: () => _showClock(context),
              child: const Text('Open Clock'),
            ),
          ),
          if (stats != null && stats.completed > 0) ...[
            const SizedBox(height: ShowdSpace.s4),
            Text(
              '${stats.currentStreak} day streak · showed up ${stats.completed} time${stats.completed == 1 ? '' : 's'}',
              style: ShowdType.caption,
            ),
          ],
        ],
      ),
    );
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

  Future<void> _restTomorrow(BuildContext context, AppController app) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final date = DateFormat('yyyy-MM-dd').format(tomorrow);
    final planned = await app.planRest(date);
    if (context.mounted) {
      showMessage(
        context,
        planned
            ? 'Rest day set for ${DateFormat('EEEE').format(tomorrow)}. Rhythm kept.'
            : 'No rest days saved yet.',
      );
    }
  }

  Future<void> _regularAlarm(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Regular alarm',
    );
    if (time == null || !context.mounted) return;
    try {
      await AlarmChannel.createNativeAlarm(
        hour: time.hour,
        minute: time.minute,
        label: 'ShowdUp',
      );
    } catch (error) {
      if (context.mounted) showMessage(context, friendlyError(error));
    }
  }

  Future<void> _showClock(BuildContext context) async {
    try {
      await AlarmChannel.showNativeAlarms();
    } catch (error) {
      if (context.mounted) showMessage(context, friendlyError(error));
    }
  }
}

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
    final today = DateUtils.isSameDay(
      a.windowStartAt.toLocal(),
      DateTime.now(),
    );
    final zone = commitment.schedule.timezone;
    final opens = zoneClock(a.windowStartAt, zone);
    final (mark, line) = switch (a.state) {
      AttemptState.pending when open => (
        MarkState.ringing,
        'Open until ${zoneClock(a.windowEndAt, zone)}',
      ),
      AttemptState.pending => (
        MarkState.ringing,
        today
            ? 'Rings today'
            : 'Rings ${DateFormat('EEEE').format(a.windowStartAt.toLocal())}',
      ),
      _ when a.restCovered => (MarkState.rest, 'Rest day. Rhythm kept.'),
      AttemptState.completed => (MarkState.showedUp, 'Showed up today'),
      AttemptState.abandoned => (
        MarkState.missed,
        'Ended today. Tomorrow, then.',
      ),
      AttemptState.expired => (
        MarkState.missed,
        'Missed today. Never miss twice.',
      ),
      AttemptState.unverifiable => (
        MarkState.unverifiable,
        'Your phone couldn’t tell. Not on you.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShowdMark(state: mark, size: 28),
            const SizedBox(width: ShowdSpace.s3),
            Expanded(child: Text(line, style: ShowdType.label)),
          ],
        ),
        const SizedBox(height: ShowdSpace.s3),
        BigNumber(
          opens,
          color: open ? ShowdColors.accent : ShowdColors.paper,
          semanticLabel: 'Alarm at $opens',
        ),
        const SizedBox(height: ShowdSpace.s2),
        Text(commitment.title, style: ShowdType.titleL),
        const SizedBox(height: ShowdSpace.s1),
        Text(goalDescription(commitment), style: ShowdType.bodyM),
        if (open) ...[
          const SizedBox(height: ShowdSpace.s6),
          ProofBar(progress: progress),
        ],
        const SizedBox(height: ShowdSpace.s6),
        ShowdButton(
          label: a.state.isTerminal
              ? 'See today'
              : open
              ? (app.progress.containsKey(a.id) ? 'Keep proving' : 'Prove it')
              : 'See the plan',
          onPressed: () => openAttempt(context, a),
        ),
      ],
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
    final (title, body, action, onPressed) = active.isNotEmpty
        ? (
            'Nothing rings today.',
            'Next: ${DateFormat('EEE d MMM, HH:mm').format(nextWindow(active.first.schedule, now).toLocal())}.',
            'See the alarm',
            () => openWizard(context, commitment: active.first),
          )
        : drafts.isNotEmpty
        ? (
            'One step left.',
            '${drafts.first.title} needs Android access before it can ring.',
            'Finish setup',
            () => openWizard(context, commitment: drafts.first),
          )
        : (
            'No alarm yet.',
            'Pick one thing you want to show up for. Small enough to repeat.',
            'Set my first alarm',
            () => openWizard(context),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ShowdSpace.s8),
        const ShowdMark(state: MarkState.ringing, size: 72),
        const SizedBox(height: ShowdSpace.s6),
        Text(title, style: ShowdType.hero),
        const SizedBox(height: ShowdSpace.s2),
        Text(body, style: ShowdType.bodyL.copyWith(color: ShowdColors.stone)),
        const SizedBox(height: ShowdSpace.s6),
        ShowdButton(
          key: active.isEmpty && drafts.isEmpty
              ? ShowdKeys.createFirstCommitment
              : null,
          label: action,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _Offer extends StatelessWidget {
  const _Offer({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
    decoration: BoxDecoration(
      color: ShowdColors.carbon,
      borderRadius: BorderRadius.circular(ShowdRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ShowdType.titleM),
        const SizedBox(height: ShowdSpace.s1),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(body, style: ShowdType.bodyM),
        ),
        Wrap(
          children: [
            TextButton(onPressed: onAction, child: Text(action)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: ShowdColors.stone),
              onPressed: onDismiss,
              child: const Text('Keep it'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.moment, this.onOpen, this.onDismiss});

  final ProNudgeMoment moment;
  final VoidCallback? onOpen;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
    decoration: BoxDecoration(
      color: ShowdColors.carbon,
      borderRadius: BorderRadius.circular(ShowdRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(moment.title, style: ShowdType.titleM)),
            ShowdIconButton(
              icon: ShowdIcons.close,
              semanticLabel: 'Dismiss',
              color: ShowdColors.stone,
              onPressed: onDismiss,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(moment.body, style: ShowdType.bodyM),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onOpen, child: const Text('See Pro')),
        ),
      ],
    ),
  );
}
