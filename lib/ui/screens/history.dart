import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/mark.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../models/attempt.dart';
import '../../models/enums.dart';
import '../../services/controller.dart';
import '../../services/rhythm.dart';
import '../app_provider.dart';
import 'common.dart';

/// Free history reaches back this far; Pro keeps two years.
const freeHistoryDays = 30;

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  AttemptState? filter;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final now = DateTime.now();
    final isPro = app.user?.isPro == true;
    final rhythm = Rhythm.of(app.attempts, now);
    final cutoff = now.subtract(const Duration(days: freeHistoryDays));
    final visible =
        app.attempts
            .where(
              (a) =>
                  (isPro || a.windowEndAt.isAfter(cutoff)) &&
                  (filter == null || a.state == filter),
            )
            .toList()
          ..sort((a, b) => b.windowStartAt.compareTo(a.windowStartAt));
    final hidden =
        !isPro && app.attempts.any((a) => !a.windowEndAt.isAfter(cutoff));
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ShowdSpace.gutter,
        ShowdSpace.s4,
        ShowdSpace.gutter,
        ShowdSpace.s8,
      ),
      children: [
        const SectionLabel('Rhythm · last 4 weeks'),
        BigNumber(
          rhythm.percent == null ? '–' : '${rhythm.percent}%',
          semanticLabel: rhythm.percent == null
              ? 'No rhythm yet'
              : 'Rhythm ${rhythm.percent} percent',
        ),
        Text(
          rhythm.counted == 0
              ? 'Your first finished alarm starts it.'
              : 'Showed up for ${rhythm.kept} of ${rhythm.counted} alarms. Rest days and phone trouble never count against you.',
          style: ShowdType.bodyM,
        ),
        const SizedBox(height: ShowdSpace.s6),
        _DayGrid(attempts: app.attempts, now: now),
        const SizedBox(height: ShowdSpace.s2),
        Text(
          'Longest streak ${app.user?.stats.longestStreak ?? 0}',
          style: ShowdType.caption,
        ),
        if (isPro && rhythm.counted > 0) ...[
          const SizedBox(height: ShowdSpace.s8),
          ..._patterns(app),
        ],
        const SizedBox(height: ShowdSpace.s8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (value, label) in [
                (null, 'All'),
                (AttemptState.completed, 'Showed up'),
                (AttemptState.expired, 'Missed'),
                (AttemptState.abandoned, 'Ended'),
                (AttemptState.unverifiable, 'Couldn’t tell'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: ShowdSpace.s2),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: filter == value,
                    onSelected: (_) => setState(() => filter = value),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: ShowdSpace.s3),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s6),
            child: Text(
              'Nothing here yet. Every alarm you finish lands here.',
              style: ShowdType.bodyM,
            ),
          ),
        for (final a in visible)
          AttemptRow(a, app.commitment(a.commitmentId)?.title ?? 'Alarm'),
        if (!isPro && (hidden || visible.isNotEmpty))
          ShowdRow(
            leading: const ShowdIcon(ShowdIcons.history),
            title: 'Older than 30 days',
            subtitle: 'Pro keeps two years.',
            trailing: const ProPill(),
            onTap: () => openPro(context),
          ),
      ],
    );
  }

  List<Widget> _patterns(AppController app) {
    final completed = app.attempts
        .where((a) => a.state == AttemptState.completed)
        .toList();
    final byWeekday = <int, int>{};
    for (final attempt in completed) {
      byWeekday.update(
        attempt.windowStartAt.weekday,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final best = byWeekday.entries.isEmpty
        ? null
        : (byWeekday.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final reminders = completed.isEmpty
        ? 0.0
        : completed.fold<int>(0, (sum, a) => sum + a.remindersFired) /
              completed.length;
    return [
      const SectionLabel('Patterns'),
      const SizedBox(height: ShowdSpace.s2),
      ShowdRow(
        title: 'Reminders before you went',
        trailing: Text(reminders.toStringAsFixed(1), style: ShowdType.titleM),
      ),
      if (best != null)
        ShowdRow(
          title: 'Your strongest day',
          trailing: Text(
            DateFormat('EEEE').format(DateTime(2026, 9, 7 + best - 1)),
            style: ShowdType.titleM,
          ),
        ),
      const SizedBox(height: ShowdSpace.s3),
      ShowdButton(
        label: 'Send a buddy check-in',
        icon: ShowdIcons.share,
        tone: ShowdButtonTone.outline,
        onPressed: () => _shareBuddySummary(app),
      ),
    ];
  }

  Future<void> _shareBuddySummary(AppController app) async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final recent = app.attempts
        .where((a) => a.state.isTerminal && a.windowEndAt.isAfter(since))
        .toList();
    final kept = recent.where((a) => a.state == AttemptState.completed).length;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'ShowdUp check-in: I showed up for $kept of ${recent.length} alarms this week. Keep me honest. #ShowdUp',
      ),
    );
  }
}

/// Four weeks of marks, oldest first, one per day.
class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.attempts, required this.now});

  final List<Attempt> attempts;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 27; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return Column(
      children: [
        for (var week = 0; week < 4; week++)
          Row(
            children: [
              for (final day in days.skip(week * 7).take(7))
                Expanded(child: _cell(day, DateUtils.isSameDay(day, today))),
            ],
          ),
      ],
    );
  }

  Widget _cell(DateTime day, bool isToday) {
    final dayAttempts = attempts.where(
      (a) => DateUtils.isSameDay(a.windowStartAt.toLocal(), day),
    );
    bool has(AttemptState state) => dayAttempts.any((a) => a.state == state);
    final rested = dayAttempts.any((a) => a.restCovered);
    final (MarkState? mark, String label) = has(AttemptState.completed)
        ? (MarkState.showedUp, 'showed up')
        : rested
        ? (MarkState.rest, 'rest day')
        : has(AttemptState.expired) || has(AttemptState.abandoned)
        ? (MarkState.missed, 'missed')
        : has(AttemptState.unverifiable)
        ? (MarkState.unverifiable, 'couldn’t tell')
        : has(AttemptState.pending)
        ? (MarkState.ringing, 'open')
        : (null, 'no alarm');
    return Semantics(
      label: '${DateFormat('EEE d MMM').format(day)}: $label',
      excludeSemantics: true,
      child: SizedBox(
        height: 40,
        child: Center(
          child: mark == null
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday
                        ? ShowdColors.stone
                        : ShowdColors.graphiteStrong,
                  ),
                )
              : ShowdMark(
                  state: mark,
                  size: 26,
                  lineColor: mark == MarkState.missed
                      ? ShowdColors.missed
                      : ShowdColors.paper,
                ),
        ),
      ),
    );
  }
}
