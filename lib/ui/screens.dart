import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../core/config.dart';
import '../core/features.dart';
import '../core/scheduling.dart';
import '../models/attempt.dart';
import '../models/commitment.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/alarm_channel.dart';
import '../platform/overlay_channel.dart';
import '../services/billing.dart';
import '../services/controller.dart';
import '../services/social_service.dart';
import 'app.dart';
import 'keys.dart';
import 'widgets.dart';
import 'wizard.dart';

void openWizard(BuildContext context, {Commitment? commitment}) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CommitmentWizard(existing: commitment),
      ),
    );
void openAttempt(BuildContext context, Attempt a) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => AttemptScreen(attemptId: a.id)),
);

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.trailing});
  final String title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22, top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(subtitle),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class AlarmModePanel extends StatelessWidget {
  const AlarmModePanel({super.key});

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
        label: 'ShowdUp regular alarm',
      );
    } catch (error) {
      if (context.mounted) showMessage(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('Start here'),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _AlarmMode(
              icon: Icons.alarm,
              title: 'Regular alarm',
              subtitle: 'Rings once in Clock',
              onTap: () => _regularAlarm(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _AlarmMode(
              icon: Icons.verified_outlined,
              title: 'ShowdUp alarm',
              subtitle: 'Repeats until proof',
              highlighted: true,
              onTap: () => openWizard(context),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            try {
              await AlarmChannel.showNativeAlarms();
            } catch (error) {
              if (context.mounted) showMessage(context, friendlyError(error));
            }
          },
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('View alarms in Clock'),
        ),
      ),
    ],
  );
}

class _AlarmMode extends StatelessWidget {
  const _AlarmMode({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(T.radius),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted ? T.accent.withValues(alpha: .12) : T.surface,
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(
          color: highlighted ? T.accent : Colors.white.withValues(alpha: .05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: highlighted ? T.accent : T.text),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: T.muted, fontSize: 11)),
        ],
      ),
    ),
  );
}

class TodayScreen extends ConsumerWidget {
  const TodayScreen({
    super.key,
    this.alarmTutorialKey,
    this.proTutorialKey,
    this.progressTutorialKey,
  });
  final GlobalKey? alarmTutorialKey;
  final GlobalKey? proTutorialKey;
  final GlobalKey? progressTutorialKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), now = DateTime.now();
    final pet = app.petSnapshot;
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weeklyAttempts = app.attempts
        .where((attempt) => !attempt.windowEndAt.isBefore(weekStart))
        .toList();
    final weeklySnoozes = weeklyAttempts.fold<int>(
      0,
      (sum, attempt) => sum + attempt.snoozes,
    );
    final weeklyResets = weeklyAttempts.fold<int>(
      0,
      (sum, attempt) =>
          sum + ((attempt.evidence?['resetCount'] as num?)?.toInt() ?? 0),
    );
    final weeklyMisses = weeklyAttempts
        .where(
          (attempt) =>
              attempt.state == AttemptState.expired ||
              attempt.state == AttemptState.abandoned,
        )
        .length;
    final today =
        app.attempts
            .where(
              (a) =>
                  a.windowEndAt.isAfter(
                    now.subtract(const Duration(hours: 6)),
                  ) &&
                  a.windowStartAt.isBefore(now.add(const Duration(hours: 24))),
            )
            .toList()
          ..sort((left, right) {
            int rank(Attempt attempt) {
              if (attempt.state == AttemptState.pending &&
                  attempt.isWindowOpen) {
                return 0;
              }
              if (attempt.state == AttemptState.pending) return 1;
              return 2;
            }

            final byRank = rank(left).compareTo(rank(right));
            if (byRank != 0) return byRank;
            return left.windowStartAt.compareTo(right.windowStartAt);
          });
    final active = app.commitments
        .where((c) => c.status == CommitmentStatus.active)
        .toList();
    final drafts = app.commitments
        .where((c) => c.status == CommitmentStatus.draft)
        .toList();
    final a = today.isEmpty ? null : today.first;
    final c = a == null ? null : app.commitment(a.commitmentId);
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeading(
            'Today',
            DateFormat('EEEE, MMMM d').format(now),
            trailing: PetScoreChip(
              glyph: pet.mascot.fallbackGlyph,
              score: pet.weeklyScore,
              mood: pet.mood.wire,
            ),
          ),
          KeyedSubtree(key: alarmTutorialKey, child: const AlarmModePanel()),
          const SizedBox(height: 14),
          if (app.user?.isPro != true) ...[
            InkWell(
              key: proTutorialKey,
              borderRadius: BorderRadius.circular(T.radius),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ProScreen()),
              ),
              child: const Panel(
                padding: 16,
                child: Row(
                  children: [
                    Icon(Icons.lock_open_rounded, color: T.accent),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Make it harder to escape',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Pro blocks selected apps during your promise',
                            style: TextStyle(color: T.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: T.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (app.error != null) ErrorNotice(app.error!, onRetry: app.refresh),
          if (app.loading)
            const Center(child: CircularProgressIndicator())
          else if (a != null && c != null) ...[
            Panel(
              key: progressTutorialKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(child: Eyebrow('Your next promise')),
                      StatePill(a.state),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    c.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    goalDescription(c),
                    style: const TextStyle(color: T.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ProgressOrbit(
                      progress: a.state == AttemptState.completed
                          ? 1
                          : app.progress[a.id] ?? (app.preview ? 0.64 : 0),
                      value: a.state == AttemptState.completed
                          ? 'Done'
                          : c.verifierConfig is StepsConfig
                          ? '${((app.progress[a.id] ?? (app.preview ? 0.64 : 0)) * (c.verifierConfig as StepsConfig).targetSteps).round()}'
                          : null,
                      label: switch (c.verifierType) {
                        VerifierType.steps => 'STEPS RECORDED',
                        VerifierType.location =>
                          c.kind == CommitmentKind.gym
                              ? 'GYM ARRIVAL'
                              : 'PLACE ARRIVAL',
                        VerifierType.walk => 'WALK PROGRESS',
                        VerifierType.focus => 'FOCUS PROGRESS',
                        VerifierType.healthWorkout => 'WORKOUT PROGRESS',
                        VerifierType.leetcode => 'LEETCODE PROGRESS',
                      },
                      color: a.state == AttemptState.completed
                          ? T.ok
                          : T.accent,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 17, color: T.muted),
                      const SizedBox(width: 8),
                      Text(
                        '${c.schedule.windowStartLocal} – ${c.schedule.windowEndLocal}',
                        style: const TextStyle(color: T.muted, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        c.schedule.timezone,
                        style: const TextStyle(color: T.muted, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => openAttempt(context, a),
                    child: Text(
                      a.state.isTerminal
                          ? 'View today’s result  →'
                          : a.isWindowOpen
                          ? 'Open my commitment  →'
                          : 'See the plan  →',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            if (today.length > 1) ...[
              const SizedBox(height: 20),
              ...today
                  .skip(1)
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AttemptTile(
                        a,
                        app.commitment(a.commitmentId)?.title ?? 'Commitment',
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 20),
          ] else ...[
            Panel(
              key: progressTutorialKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    active.isEmpty
                        ? drafts.isNotEmpty
                              ? Icons.warning_amber_rounded
                              : Icons.flag_outlined
                        : Icons.nights_stay_outlined,
                    color: T.accent,
                    size: 40,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    active.isEmpty
                        ? drafts.isNotEmpty
                              ? 'Your draft needs\none more step.'
                              : 'One promise.\nA place to start.'
                        : 'You have a plan.',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    active.isEmpty
                        ? drafts.isNotEmpty
                              ? 'Enable the required Android access to activate ${drafts.first.title}. Nothing is scheduled while it remains a draft.'
                              : 'A walk, gym visit, place arrival, Focus session or accepted problem. Pick something small enough to repeat.'
                        : 'Your next window opens ${DateFormat('EEE, MMM d · HH:mm').format(nextWindow(active.first.schedule, now).toLocal())}. Reminders follow your chosen schedule.',
                    style: const TextStyle(color: T.muted, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: active.isEmpty && drafts.isEmpty
                        ? ShowdKeys.createFirstCommitment
                        : null,
                    onPressed: () => active.isEmpty
                        ? drafts.isNotEmpty
                              ? openWizard(context, commitment: drafts.first)
                              : openWizard(context)
                        : openWizard(context, commitment: active.first),
                    child: Text(
                      active.isEmpty
                          ? drafts.isNotEmpty
                                ? 'Finish setup  →'
                                : 'Create a commitment  +'
                          : 'View commitment',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          Row(
            children: [
              Expanded(
                child: _Stat(
                  '${app.user?.stats.currentStreak ?? 0}',
                  'CURRENT STREAK',
                  Icons.local_fire_department_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  '${app.user?.stats.completed ?? 0}',
                  'TIMES SHOWED UP',
                  Icons.check_circle_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _FrictionCard(
            snoozes: weeklySnoozes,
            focusResets: weeklyResets,
            misses: weeklyMisses,
            isPro: app.user?.isPro == true,
            onOpenPro: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ProScreen()),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.icon);
  final String value, label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Panel(
    padding: 18,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: T.accent, size: 21),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            color: T.muted,
            fontSize: 8,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _FrictionCard extends StatelessWidget {
  const _FrictionCard({
    required this.snoozes,
    required this.focusResets,
    required this.misses,
    required this.isPro,
    required this.onOpenPro,
  });

  final int snoozes;
  final int focusResets;
  final int misses;
  final bool isPro;
  final VoidCallback onOpenPro;

  @override
  Widget build(BuildContext context) {
    final total = snoozes + focusResets + misses;
    return Panel(
      color: T.surfaceRaised,
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: T.accent, size: 20),
              SizedBox(width: 10),
              Eyebrow('Friction map · this week', color: T.accent),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            total == 0
                ? 'Nothing is fighting the plan yet.'
                : '$total moments tried to break the plan.',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _frictionPill('$snoozes snoozes'),
              _frictionPill('$focusResets distractions'),
              _frictionPill('$misses misses'),
            ],
          ),
          if (!isPro && total > 0) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onOpenPro,
              icon: const Icon(Icons.lock_outline_rounded, size: 17),
              label: const Text('Turn friction into guardrails'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _frictionPill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: T.bg.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: T.outline),
    ),
    child: Text(label, style: const TextStyle(color: T.muted, fontSize: 11)),
  );
}

String goalDescription(Commitment c) {
  final cfg = c.verifierConfig;
  return cfg is StepsConfig
      ? '${NumberFormat.decimalPattern().format(cfg.targetSteps)} new steps inside your window'
      : cfg is WalkConfig
      ? switch (cfg.mode) {
          WalkGoalMode.duration =>
            '${cfg.targetDurationMs ~/ 60000} active walking minutes',
          WalkGoalMode.distance =>
            '${(cfg.targetDistanceM / 1000).toStringAsFixed(2)} km by GPS',
          WalkGoalMode.destination =>
            'Walk to ${cfg.label?.isNotEmpty == true ? cfg.label : 'your destination'}',
        }
      : cfg is LocationConfig
      ? 'Stay near ${cfg.label?.isNotEmpty == true ? cfg.label : 'your destination'} for ${cfg.dwellMs ~/ 60000} minutes'
      : cfg is FocusConfig
      ? '${cfg.targetDurationMs ~/ 60000} uninterrupted minutes away from ${cfg.packages.length} selected apps'
      : cfg is HealthWorkoutConfig
      ? '${cfg.targetDurationMs ~/ 60000} sensor-recorded Health Connect minutes · ${cfg.activityType}'
      : cfg is LeetCodeConfig
      ? '${cfg.targetAccepted} accepted problem${cfg.targetAccepted == 1 ? '' : 's'} on @${cfg.username}'
      : '';
}

String proofDescription(Commitment c) => switch (c.verifierConfig) {
  WalkConfig() =>
    'Foreground GPS counts plausible movement with fresh, precise, non-mock fixes. Tracking starts here or from the first reminder.',
  LocationConfig(:final dwellMs) =>
    'Foreground GPS proves a continuous ${dwellMs ~/ 60000}-minute stay inside the fixed 150 m place boundary.',
  FocusConfig() =>
    'Android reports only foreground app package changes. Ten continuous seconds in a selected app resets the uninterrupted timer.',
  HealthWorkoutConfig() =>
    'One sensor-recorded Health Connect exercise session must meet the duration. Manual and unknown records never count.',
  LeetCodeConfig() =>
    'Unique accepted submissions on the chosen public LeetCode profile must appear inside this commitment window.',
  StepsConfig() =>
    'Android’s step counter must record plausible new movement during this window.',
};

class CommitmentsScreen extends ConsumerWidget {
  const CommitmentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final cs = app.commitments
        .where((c) => c.status != CommitmentStatus.archived)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading('Promises with a plan.', 'Your commitments'),
        if (cs.isEmpty)
          const Panel(
            child: Text(
              'No commitments yet. Start with something that matters to you.',
            ),
          ),
        for (final c in cs) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: T.accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(switch (c.kind) {
                        CommitmentKind.walk => Icons.directions_run,
                        CommitmentKind.gym => Icons.fitness_center,
                        CommitmentKind.arrive => Icons.place_outlined,
                        CommitmentKind.focus => Icons.center_focus_strong,
                        CommitmentKind.workout =>
                          Icons.health_and_safety_outlined,
                        CommitmentKind.leetcode => Icons.code_rounded,
                      }, color: T.accent),
                    ),
                    const Spacer(),
                    Eyebrow(
                      c.status.wire,
                      color: c.status == CommitmentStatus.active
                          ? T.ok
                          : T.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  c.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  goalDescription(c),
                  style: const TextStyle(color: T.muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Text(
                  c.schedule.hasCustomWindows
                      ? 'Custom times by day  ·  ${_days(c.schedule.daysOfWeek)}'
                      : '${c.schedule.windowStartLocal} – ${c.schedule.windowEndLocal}  ·  ${_days(c.schedule.daysOfWeek)}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  'Every ${c.reminder.intervalMinutes} min · ${c.reminder.volumeMode.wire} · up to ${c.reminder.maxReminders} reminders',
                  style: const TextStyle(color: T.muted, fontSize: 11),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => openWizard(context, commitment: c),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Edit'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: c.status == CommitmentStatus.draft
                          ? () => openWizard(context, commitment: c)
                          : () async {
                              try {
                                await app.repository.update(c.id, {
                                  'status': c.status == CommitmentStatus.active
                                      ? 'paused'
                                      : 'active',
                                });
                              } catch (e) {
                                if (context.mounted) {
                                  showMessage(context, friendlyError(e));
                                }
                              }
                            },
                      child: Text(
                        c.status == CommitmentStatus.draft
                            ? 'Finish setup'
                            : c.status == CommitmentStatus.active
                            ? 'Pause'
                            : 'Resume',
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        try {
                          await app.repository.update(c.id, {
                            'status': 'archived',
                          });
                        } catch (e) {
                          if (context.mounted) {
                            showMessage(context, friendlyError(e));
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive commitment'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: () => openWizard(context),
          icon: const Icon(Icons.add),
          label: const Text('New commitment'),
        ),
        const SizedBox(height: 18),
        Text(
          app.user?.isPro == true
              ? 'Pro · independent schedules for every commitment'
              : 'Free forever · one active commitment, full verification',
          textAlign: TextAlign.center,
          style: const TextStyle(color: T.muted, fontSize: 11),
        ),
      ],
    );
  }

  String _days(List<int> days) => days.length == 7
      ? 'Every day'
      : days
            .map(
              (d) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1],
            )
            .join(', ');
}

class AttemptTile extends StatelessWidget {
  const AttemptTile(this.a, this.title, {super.key});
  final Attempt a;
  final String title;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () => openAttempt(context, a),
    child: Panel(
      padding: 16,
      child: Row(
        children: [
          Icon(
            a.state == AttemptState.completed
                ? Icons.check_circle_outline
                : a.state == AttemptState.unverifiable
                ? Icons.sensors_off
                : Icons.circle_outlined,
            color: stateColor(a.state),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('EEE, MMM d').format(DateTime.parse(a.date)),
                  style: const TextStyle(color: T.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          StatePill(a.state),
        ],
      ),
    ),
  );
}

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
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final terminal = app.attempts.where((a) => a.state.isTerminal).toList();
    final completed = terminal
        .where((a) => a.state == AttemptState.completed)
        .toList();
    final completionRate = terminal.isEmpty
        ? 0
        : (completed.length * 100 / terminal.length).round();
    final averageReminders = completed.isEmpty
        ? 0.0
        : completed.fold<int>(0, (sum, a) => sum + a.remindersFired) /
              completed.length;
    final completionsByWeekday = <int, int>{};
    for (final attempt in completed) {
      completionsByWeekday.update(
        attempt.windowStartAt.weekday,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final bestWeekday = completionsByWeekday.entries.isEmpty
        ? null
        : (completionsByWeekday.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final visible = app.attempts
        .where(
          (a) =>
              (app.user?.isPro == true || a.windowEndAt.isAfter(cutoff)) &&
              (filter == null || a.state == filter),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading('Look how far you’ve come.', 'Your history'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('The last seven days'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final date = DateTime.now().subtract(Duration(days: 6 - i));
                  final done = app.attempts.any(
                    (a) =>
                        DateUtils.isSameDay(a.windowStartAt, date) &&
                        a.state == AttemptState.completed,
                  );
                  return Column(
                    children: [
                      Text(
                        DateFormat('E').format(date).substring(0, 1),
                        style: const TextStyle(color: T.muted, fontSize: 10),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 32,
                        height: 36,
                        decoration: BoxDecoration(
                          color: done
                              ? T.ok.withValues(alpha: .16)
                              : Colors.white.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          done ? Icons.check : Icons.remove,
                          color: done ? T.ok : T.muted,
                          size: 17,
                        ),
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 20),
              Text(
                '${app.user?.stats.longestStreak ?? 0} commitments · your longest streak',
                style: const TextStyle(color: T.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (app.user?.isPro == true && terminal.isNotEmpty) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Your patterns'),
                const SizedBox(height: 16),
                _patternRow('Completion rate', '$completionRate%'),
                _patternRow(
                  'Reminders before completion',
                  averageReminders.toStringAsFixed(1),
                ),
                if (bestWeekday != null)
                  _patternRow(
                    'Most completions',
                    DateFormat(
                      'EEEE',
                    ).format(DateTime(2026, 9, 7 + bestWeekday - 1)),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => _shareBuddySummary(app),
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Share a buddy check-in'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You choose who receives it through Android’s share sheet. ShowdUp does not upload a buddy list.',
                  style: TextStyle(color: T.muted, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null),
              ),
              const SizedBox(width: 8),
              ...AttemptState.values
                  .where((s) => s != AttemptState.pending)
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(stateLabel(s)),
                        selected: filter == s,
                        onSelected: (_) => setState(() => filter = s),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          const Panel(
            child: Text(
              'No attempts here yet. Every time you show up, it becomes part of your story.',
            ),
          ),
        for (final a in visible) ...[
          AttemptTile(a, app.commitment(a.commitmentId)?.title ?? 'Commitment'),
          const SizedBox(height: 12),
        ],
        if (app.user?.isPro != true) ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ProScreen()),
            ),
            child: const Text('Unlock two years of history with Pro  →'),
          ),
        ],
      ],
    );
  }

  Widget _patternRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: T.muted)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Future<void> _shareBuddySummary(AppController app) async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final recent = app.attempts
        .where((attempt) => attempt.state.isTerminal)
        .where((attempt) => attempt.windowEndAt.isAfter(since))
        .toList();
    final completed = recent
        .where((attempt) => attempt.state == AttemptState.completed)
        .length;
    final opportunities = recent.length;
    final streak = app.user?.stats.currentStreak ?? 0;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'My ShowdUp buddy check-in: $completed of $opportunities commitments completed in the last 7 days. Current streak: $streak. Keep me honest next week. #ShowdUp',
      ),
    );
  }
}

class AttemptScreen extends ConsumerStatefulWidget {
  const AttemptScreen({super.key, required this.attemptId});
  final String attemptId;
  @override
  ConsumerState<AttemptScreen> createState() => _AttemptScreenState();
}

class _AttemptScreenState extends ConsumerState<AttemptScreen> {
  bool busy = false;
  final cardKey = GlobalKey();
  String? localError;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      localError = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => localError = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final matches = app.attempts.where((a) => a.id == widget.attemptId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('This commitment is no longer available.'),
        ),
      );
    }
    final a = matches.first, c = app.commitment(a.commitmentId);
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final terminal = a.state.isTerminal;
    final open = a.isWindowOpen;
    final failure = app.failures[a.id];
    return Scaffold(
      appBar: AppBar(
        title: Text(terminal ? 'Today’s result' : 'Your commitment'),
        actions: [
          if (terminal)
            IconButton(
              tooltip: 'Share result',
              onPressed: () => run(() => _share(c, a, app.preview)),
              icon: const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              RepaintBoundary(
                key: cardKey,
                child: Container(
                  color: T.bg,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Brand(size: 19),
                      const SizedBox(height: 28),
                      StatePill(a.state),
                      const SizedBox(height: 22),
                      Text(
                        c.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        goalDescription(c),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: T.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 26),
                      ProgressOrbit(
                        progress: a.state == AttemptState.completed
                            ? 1
                            : app.progress[a.id] ?? (app.preview ? 0.64 : 0),
                        color: a.state == AttemptState.completed
                            ? T.ok
                            : T.accent,
                        label: terminal
                            ? stateLabel(a.state).toUpperCase()
                            : 'ONE STEP AT A TIME',
                        value: a.state == AttemptState.completed
                            ? 'Done'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        key: terminal
                            ? ShowdKeys.attemptOutcome(a.state)
                            : null,
                        terminal
                            ? _terminalCopy(a.state)
                            : open
                            ? 'You made the plan. Now make it happen.'
                            : 'Your window hasn’t opened yet.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                      if (app.preview) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'PREVIEW · NOT A VERIFIED RESULT',
                          style: TextStyle(
                            color: T.accent,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        a.date,
                        style: const TextStyle(color: T.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Panel(
                padding: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('What counts as done'),
                    const SizedBox(height: 12),
                    Text(
                      proofDescription(c),
                      style: const TextStyle(
                        color: T.muted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (a.state == AttemptState.completed &&
                        a.evidence?['source'] != null) ...[
                      Text(
                        'Verified by ${a.evidence?['sourceLabel'] ?? a.evidence?['source']}',
                        style: const TextStyle(color: T.ok, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      '${c.schedule.windowStartLocal} – ${c.schedule.windowEndLocal} · ${c.schedule.timezone}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (localError != null) ErrorNotice(localError!),
              if (failure != null) ErrorNotice('Unable to verify. $failure'),
              if (!terminal) ...[
                if (open)
                  FilledButton(
                    onPressed: busy ? null : () => run(() => app.start(a)),
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : app.progress.containsKey(a.id)
                          ? 'Resume verification'
                          : 'Start verification',
                    ),
                  ),
                if (!open)
                  const Text(
                    'Reminders start when your window opens.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: T.muted),
                  ),
                const SizedBox(height: 10),
                if (open)
                  OutlinedButton(
                    onPressed: busy ? null : () => run(() => app.snooze(a)),
                    child: const Text('Snooze · silence this reminder'),
                  ),
                if (failure != null) ...[
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const PermissionsScreen(),
                      ),
                    ),
                    child: const Text('Check permissions'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => run(() => app.unable(a)),
                    child: const Text('Record as unable to verify'),
                  ),
                ],
                TextButton(
                  key: ShowdKeys.endToday,
                  onPressed: busy ? null : () => run(() => app.end(a)),
                  child: const Text(
                    'End today without completing',
                    style: TextStyle(color: T.muted),
                  ),
                ),
                if (app.preview)
                  TextButton(
                    onPressed: () => run(() async {
                      await app.repository.call('previewComplete', {
                        'commitmentId': a.commitmentId,
                        'date': a.date,
                      });
                    }),
                    child: const Text('Preview the completion screen'),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Ending today stops reminders and awards no completion. Tomorrow is a new opportunity.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: T.muted, fontSize: 11, height: 1.5),
                ),
              ] else
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(() => _share(c, a, app.preview)),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share my day'),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _terminalCopy(AttemptState s) => switch (s) {
    AttemptState.completed =>
      'A promise kept.\nLet that feeling carry you into the day.',
    AttemptState.abandoned =>
      'Plans change. That’s allowed.\nNo completion awarded. Tomorrow is a fresh start.',
    AttemptState.expired =>
      'This window has ended.\nMake room for your next opportunity.',
    AttemptState.unverifiable =>
      'A sensor couldn’t verify this attempt.\nYour streak is preserved. No completion awarded.',
    _ => '',
  };
  Future<void> _share(Commitment c, Attempt a, bool preview) async {
    final boundary =
        cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/showdup-${a.id}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${preview ? 'Preview: ' : ''}${stateLabel(a.state)} — ${c.title}. Small steps. Real change. #ShowdUp',
        files: [XFile(file.path)],
      ),
    );
  }
}

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  AlarmPermissionStatus? status;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      final p = await AlarmChannel.getPermissionStatus();
      if (mounted) setState(() => status = p);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> request(String which) async {
    try {
      await AlarmChannel.requestPermission(which);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Make reminders reliable')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'A little setup.\nA lot more follow-through.',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        const Text(
          'You choose what to allow. Each permission has one job, and you can change it in Android settings.',
          style: TextStyle(color: T.muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        if (error != null) ErrorNotice(error!),
        _permission(
          'Notifications',
          'See reminders and ongoing verification.',
          'notifications',
          status?.notifications,
        ),
        _permission(
          'Exact reminders',
          'Let Android deliver reminders at your chosen time. Without this, they may be delayed.',
          'exactAlarm',
          status?.exactAlarm,
        ),
        _permission(
          'Precise location',
          'Verify arrival only after you open the app. No background location permission.',
          'location',
          status?.location,
        ),
        _permission(
          'Battery settings',
          'Choose ShowdUp and allow unrestricted battery use so tracking can continue.',
          'battery',
          status == null ? null : !status!.batteryOptimised,
        ),
        _permission(
          'Full-screen reminders',
          'Optional. Android may restrict this; a notification remains available.',
          'fullScreenIntent',
          status?.fullScreenIntent,
        ),
        _permission(
          'Autostart on your phone',
          'Xiaomi, Redmi, Realme, Oppo and Vivo may need autostart enabled. Allow ShowdUp in the manufacturer’s settings.',
          'autostart',
          false,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  Widget _permission(
    String title,
    String copy,
    String which,
    bool? granted,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      padding: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                granted == true ? Icons.check_circle : Icons.settings_outlined,
                color: granted == true ? T.ok : T.accent,
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            copy,
            style: const TextStyle(color: T.muted, fontSize: 12, height: 1.6),
          ),
          TextButton(
            onPressed: () => request(which),
            child: Text(
              granted == true ? 'Review in settings' : 'Open settings / allow',
            ),
          ),
        ],
      ),
    ),
  );
}

class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});
  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  bool busy = false;
  String? message;
  Future<void> run(Future<BillingResult> Function() action) async {
    setState(() => busy = true);
    try {
      final result = await action();
      setState(
        () => message = switch (result) {
          BillingResult.purchased => 'Pro is now active on this device.',
          BillingResult.restored when Billing.isPro =>
            'Your Pro purchase has been restored.',
          BillingResult.restored =>
            'No active Pro purchase was found for this Google Play account.',
          BillingResult.cancelled => 'No changes were made.',
        },
      );
    } catch (e) {
      setState(() => message = friendlyError(e));
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Eyebrow('ShowdUp Pro', color: T.accent),
          const SizedBox(height: 18),
          const Text(
            'Make room for\nmore of you.',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Independent commitments. Your complete history. More ways to keep showing up.',
            style: TextStyle(color: T.muted, height: 1.6),
          ),
          const SizedBox(height: 28),
          for (final entry in [
            (
              'Unlock after completion',
              'Selected distracting apps stay covered during the commitment window until evidence completes it or you end today.',
            ),
            (
              'Advanced weekly schedules',
              'Use multiple commitments and set a different time window for each weekday.',
            ),
            (
              'Two years of history',
              'Review up to two years of attempts, beyond the free seven days.',
            ),
            (
              'Buddy check-ins',
              'Share a seven-day progress summary with someone you trust.',
            ),
            (
              'The same trusted verification',
              'Verification quality and the emergency exit stay free.',
            ),
          ]) ...[
            Panel(
              padding: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, color: T.accent, size: 20),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.$2,
                          style: const TextStyle(
                            color: T.muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          const Text(
            'You choose which apps are restricted. ShowdUp, Android Settings, calling, and emergency tools always remain available.',
            style: TextStyle(color: T.muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 24),
          if (message != null) ErrorNotice(message!),
          FilledButton(
            onPressed: busy || app.user?.isPro == true
                ? null
                : () => run(Billing.paywall),
            child: Text(
              app.user?.isPro == true
                  ? 'You have Pro'
                  : busy
                  ? 'Please wait…'
                  : 'View plans & pricing',
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => run(Billing.restore),
            child: const Text('Restore purchases'),
          ),
          const Text(
            'Prices and renewal periods are shown before purchase. Subscriptions renew automatically unless canceled in Google Play. Removing this app or its data does not cancel a subscription.',
            textAlign: TextAlign.center,
            style: TextStyle(color: T.muted, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.onReplayTutorial,
  });
  final Future<void> Function() onLogout;
  final VoidCallback onReplayTutorial;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading('Your app, your rules.', 'Settings'),
        Panel(
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: T.accent.withValues(alpha: .15),
                foregroundColor: T.accent,
                child: const Icon(Icons.person_outline),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.user?.displayName.isNotEmpty == true
                          ? app.user!.displayName
                          : 'Your account',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      app.preview
                          ? 'Local preview'
                          : app.user?.isPro == true
                          ? 'ShowdUp Pro'
                          : 'ShowdUp Free',
                      style: const TextStyle(color: T.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _tile(
          context,
          Icons.help_outline_rounded,
          'Replay tutorial',
          'Show the alarm and verification walkthrough again',
          onReplayTutorial,
        ),
        _tile(
          context,
          Icons.notifications_active_outlined,
          'Permissions & reliability',
          'Location, reminders and battery',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const PermissionsScreen()),
          ),
        ),
        _tile(
          context,
          Icons.picture_in_picture_alt_outlined,
          'Pet overlay',
          'Optional pet and stats over other apps',
          () async {
            try {
              final status = await OverlayChannel.status();
              if (!status.permissionGranted) {
                await OverlayChannel.requestPermission();
                return;
              }
              if (status.enabled) {
                await OverlayChannel.disable();
              } else {
                await OverlayChannel.enable();
              }
              if (context.mounted) {
                showMessage(
                  context,
                  status.enabled
                      ? 'Pet overlay turned off.'
                      : 'Pet overlay enabled.',
                );
              }
            } catch (e) {
              if (context.mounted) showMessage(context, friendlyError(e));
            }
          },
        ),
        _tile(
          context,
          Icons.auto_awesome_outlined,
          'Explore Pro',
          'More commitments and two years of history',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ProScreen()),
          ),
        ),
        _tile(
          context,
          Icons.shield_outlined,
          'Privacy & verification',
          'What we collect and what we can prove',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
          ),
        ),
        const SizedBox(height: 20),
        const Panel(
          padding: 20,
          child: Text(
            'You always have an exit.\n“End today without completing” stops reminders and awards nothing. A sensor failure is never your failure.',
            style: TextStyle(color: T.muted, fontSize: 13, height: 1.8),
          ),
        ),
        const SizedBox(height: 24),
        if (app.preview)
          OutlinedButton(
            onPressed: onLogout,
            child: const Text('Leave preview'),
          ),
        if (!app.preview)
          TextButton(
            onPressed: () async {
              final accepted = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete local data?'),
                  content: const Text(
                    'This permanently deletes commitments and history stored on this device. Your RevenueCat/Google Play subscription is separate and must be canceled in Google Play.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep data'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete local data'),
                    ),
                  ],
                ),
              );
              if (accepted == true) {
                try {
                  await SocialService.instance.deleteAccount();
                  await app.repository.call('deleteAccount', {});
                  await onLogout();
                } catch (e) {
                  if (context.mounted) showMessage(context, friendlyError(e));
                }
              }
            },
            child: const Text(
              'Delete local data',
              style: TextStyle(color: T.danger),
            ),
          ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'ShowdUp 1.0.0 · Made for follow-through',
            style: TextStyle(color: T.muted, fontSize: 10),
          ),
        ),
        if (app.preview && !AppConfig.configured)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Preview uses sample data and does not make purchases or run live verification.',
              textAlign: TextAlign.center,
              style: TextStyle(color: T.muted, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String sub,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 5),
    leading: Icon(icon, color: T.accent),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(sub, style: const TextStyle(color: T.muted, fontSize: 11)),
    trailing: const Icon(Icons.chevron_right, size: 19),
    onTap: action,
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & verification')),
    body: ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Trust comes first.',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 22),
        for (final section in [
          (
            'Your data',
            'Commitments, attempt history, reminders and verification evidence stay on this device. If you use Battles, Firebase receives your chosen display identity, mascot, battle membership and aggregated outcome, snooze, score and pet-state events. Commitment titles, step readings, coordinates and verification evidence are not uploaded for Battles. RevenueCat receives an anonymous app-user identifier and subscription status.',
          ),
          (
            'Walks',
            'Walk verification starts when you open the commitment or its first reminder fires. Foreground GPS measures plausible movement for active time or distance. ShowdUp rejects mock, stale and low-accuracy fixes, but this still proves phone movement rather than exercise intensity.',
          ),
          (
            'Location',
            'Gym verification uses a foreground service to check five continuous minutes inside a fixed 150 m boundary. Place-search text and the selected place are processed by Google Places; the resulting place and completion coordinates stay in local commitment storage. ShowdUp does not request background location permission.',
          ),
          (
            'Selected-app restrictions',
            'Focus users can optionally enable Android Accessibility access to identify only which selected foreground app opens and reset a local timer after ten seconds. Pro can additionally show a blocking screen. ShowdUp does not read screen content, typed text, notifications or passwords. ShowdUp, Android Settings, permission controls, the default dialer and recognized emergency packages are excluded. You can disable the service at any time in Android Accessibility settings.',
          ),
          if (Features.workout)
            (
              'Health Connect workouts',
              'Workout verification reads only exercise-session time, type, recording method, source app and device attribution. Manual and unknown records, routes, heart rate and other health data are not read. The evidence remains on this device.',
            ),
          if (Features.leetcode)
            (
              'LeetCode',
              'ShowdUp sends the username you enter to LeetCode and reads recent accepted submissions visible on that public profile. It never asks for or stores a LeetCode password or session cookie. If the public service is unavailable, the attempt is unable to verify rather than missed.',
            ),
          (
            'Pet overlay',
            'The optional “Display over other apps” permission shows your pet, score and accountability controls over other apps. A persistent notification identifies ShowdUp while it runs. The overlay does not read or capture content from the app underneath it and can be disabled from the overlay, notification or ShowdUp settings.',
          ),
          (
            'Your controls',
            'End an attempt at any time without earning completion. Revoke permissions in Android settings. Delete local data from Settings to remove commitments and attempt history from this device.',
          ),
          (
            'Subscriptions',
            'Payments and renewal terms are displayed by Google Play. Manage or cancel subscriptions in Google Play. Deleting local data or uninstalling ShowdUp does not cancel billing.',
          ),
          (
            'Permission failures',
            'Missing sensors, revoked permissions and unavailable GPS show “Unable to verify.” These attempts award no completion and preserve your streak.',
          ),
        ]) ...[
          Text(
            section.$1,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            section.$2,
            style: const TextStyle(color: T.muted, height: 1.7, fontSize: 14),
          ),
          const SizedBox(height: 26),
        ],
        if (AppConfig.privacyPolicyUrl.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () async {
              final opened = await launchUrl(
                Uri.parse(AppConfig.privacyPolicyUrl),
                mode: LaunchMode.externalApplication,
              );
              if (!opened && context.mounted) {
                showMessage(context, 'Could not open the privacy policy.');
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open the full privacy policy'),
          ),
      ],
    ),
  );
}
