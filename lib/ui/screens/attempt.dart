import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
import '../../platform/blocker_channel.dart';
import '../../services/controller.dart';
import '../app_provider.dart';
import '../keys.dart';
import 'common.dart';
import 'permissions.dart';

class AttemptScreen extends ConsumerStatefulWidget {
  const AttemptScreen({super.key, required this.attemptId});
  final String attemptId;

  @override
  ConsumerState<AttemptScreen> createState() => _AttemptScreenState();
}

class _AttemptScreenState extends ConsumerState<AttemptScreen> {
  bool busy = false;
  bool released = false;
  final cardKey = GlobalKey();
  String? localError;

  /// Names of the apps this alarm holds, for "Open Instagram".
  Map<String, String> appNames = const {};
  bool loadingNames = false;

  Future<void> _loadAppNames(Commitment c) async {
    if (loadingNames || appNames.isNotEmpty) return;
    final packages = c.restrictions.packages;
    if (!c.restrictions.enabled || packages.isEmpty) return;
    loadingNames = true;
    try {
      final names = await BlockerChannel.appLabels(packages);
      if (mounted) setState(() => appNames = names);
    } catch (_) {
      // Names are a nicety; the button falls back to "Open your app".
    }
  }

  /// Ending today can spend a saved rest day instead.
  Future<void> _endToday(AppController app, Attempt a) async {
    final banked = app.restBanked;
    if (banked == null || banked == 0) return run(() => app.end(a));
    final useRest = await showShowdSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('End today?', style: ShowdType.titleL),
          const SizedBox(height: ShowdSpace.s2),
          Text(
            'Reminders stop either way. A rest day keeps your streak and rhythm.',
            style: ShowdType.bodyM,
          ),
          const SizedBox(height: ShowdSpace.s6),
          ShowdButton(
            label: 'Use a rest day ($banked left)',
            icon: ShowdIcons.rest,
            onPressed: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: ShowdSpace.s2),
          ShowdButton(
            label: 'End without one',
            tone: ShowdButtonTone.quiet,
            onPressed: () => Navigator.pop(sheetContext, false),
          ),
        ],
      ),
    );
    if (useRest == null) return;
    return run(() => app.end(a, rest: useRest));
  }

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
        body: SafeArea(
          child: Column(
            children: [
              const PushedHeader(),
              Expanded(
                child: Center(
                  child: Text('This alarm is gone.', style: ShowdType.bodyL),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final a = matches.first;
    final c = app.commitment(a.commitmentId);
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (a.state == AttemptState.completed) {
      if (!released) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => released = true);
        });
      }
      _loadAppNames(c);
      return _released(app, a, c);
    }
    if (a.state.isTerminal) return _result(app, a, c);
    return _proof(app, a, c);
  }

  Widget _proof(AppController app, Attempt a, Commitment c) {
    final open = a.isWindowOpen;
    final failure = app.failures[a.id];
    final tracking = app.progress.containsKey(a.id);
    final progress = app.progress[a.id] ?? (app.preview ? .64 : 0.0);
    final number = proofNumber(c, progress);
    final snoozeCost = a.snoozes < 8;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PushedHeader(
              title: open
                  ? 'Open now'
                  : 'Opens at ${zoneClock(a.windowStartAt, c.schedule.timezone)}',
              trailing: ShowdIconButton(
                icon: ShowdIcons.info,
                semanticLabel: 'How it’s proven',
                onPressed: () => _proofSheet(a, c),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ShowdSpace.gutter,
                  ShowdSpace.s4,
                  ShowdSpace.gutter,
                  ShowdSpace.s6,
                ),
                children: [
                  Text(c.title, style: ShowdType.titleXL),
                  const SizedBox(height: ShowdSpace.s2),
                  Text(goalDescription(c), style: ShowdType.bodyM),
                  if (c.reason?.isNotEmpty == true) ...[
                    const SizedBox(height: ShowdSpace.s3),
                    Text(
                      '“${c.reason}”',
                      style: ShowdType.bodyL.copyWith(
                        color: ShowdColors.paper,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (c.verifierType == VerifierType.leetcode) ...[
                    const SizedBox(height: ShowdSpace.s2),
                    Text(
                      'Beta · if LeetCode can’t be reached, it won’t count as a miss.',
                      style: ShowdType.caption,
                    ),
                  ],
                  const SizedBox(height: ShowdSpace.s8),
                  BigNumber(
                    number.value,
                    color: progress > 0
                        ? ShowdColors.accent
                        : ShowdColors.paper,
                    semanticLabel: '${number.value} ${number.unit}',
                  ),
                  Text(number.unit, style: ShowdType.label),
                  const SizedBox(height: ShowdSpace.s4),
                  ProofBar(progress: progress),
                  const SizedBox(height: ShowdSpace.s4),
                  Text(
                    !open
                        ? 'Reminders start when the window opens.'
                        : tracking
                        ? 'Pocket the phone. It’s counting.'
                        : 'Start, then pocket the phone.',
                    style: ShowdType.bodyM,
                  ),
                  if (app.preview) ...[
                    const SizedBox(height: ShowdSpace.s2),
                    Text(
                      'Preview · not a verified result',
                      style: ShowdType.caption.copyWith(
                        color: ShowdColors.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: ShowdSpace.s6),
                  if (localError != null) ShowdNotice(localError!),
                  if (failure != null) ...[
                    ShowdNotice('Couldn’t check this yet. $failure'),
                    ShowdRow(
                      leading: const ShowdIcon(ShowdIcons.bell),
                      title: 'Check permissions',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const PermissionsScreen(),
                        ),
                      ),
                    ),
                    ShowdRow(
                      leading: const ShowdIcon(ShowdIcons.info),
                      title: 'My phone can’t check this today',
                      subtitle: 'No points, and your streak stays.',
                      onTap: busy ? null : () => run(() => app.unable(a)),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ShowdSpace.gutter,
                ShowdSpace.s2,
                ShowdSpace.gutter,
                ShowdSpace.s4,
              ),
              child: Column(
                children: [
                  if (open) ...[
                    ShowdButton(
                      label: c.verifierConfig is TagScanConfig
                          ? 'Scan my tag'
                          : tracking
                          ? 'Keep proving'
                          : 'Start proving',
                      icon: c.verifierConfig is TagScanConfig
                          ? ShowdIcons.tagScan
                          : null,
                      busy: busy,
                      onPressed: () => run(() => app.start(a)),
                    ),
                    const SizedBox(height: ShowdSpace.s3),
                  ],
                  HoldToConfirmButton(
                    key: ShowdKeys.endToday,
                    label: 'Hold to end today',
                    enabled: !busy,
                    onConfirmed: () => _endToday(app, a),
                  ),
                  if (open)
                    ShowdButton(
                      label: snoozeCost
                          ? 'Snooze this reminder · −5 points'
                          : 'Snooze this reminder',
                      tone: ShowdButtonTone.quiet,
                      onPressed: busy ? null : () => run(() => app.snooze(a)),
                    ),
                  if (app.preview)
                    ShowdButton(
                      label: 'Preview the Released screen',
                      tone: ShowdButtonTone.quiet,
                      onPressed: () => run(
                        () => app.repository.call('previewComplete', {
                          'commitmentId': a.commitmentId,
                          'date': a.date,
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _result(AppController app, Attempt a, Commitment c) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const PushedHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ShowdSpace.gutter,
              ),
              children: [
                const SizedBox(height: ShowdSpace.s12),
                Center(child: ShowdMark(state: attemptMark(a), size: 96)),
                const SizedBox(height: ShowdSpace.s8),
                Text(
                  key: ShowdKeys.attemptOutcome(a.state),
                  switch (a.state) {
                    _ when a.restCovered => 'Rest day.\nRhythm kept.',
                    AttemptState.abandoned =>
                      'Ended today.\nNo points, no guilt.',
                    AttemptState.expired => 'Missed today.\nNever miss twice.',
                    _ =>
                      'Your phone couldn’t tell.\nNot on you. Your streak is safe.',
                  },
                  textAlign: TextAlign.center,
                  style: ShowdType.titleXL,
                ),
                const SizedBox(height: ShowdSpace.s4),
                Text(
                  '${c.title} · ${DateFormat('EEE d MMM').format(DateTime.parse(a.date))}',
                  textAlign: TextAlign.center,
                  style: ShowdType.bodyM,
                ),
                if (app.preview) ...[
                  const SizedBox(height: ShowdSpace.s2),
                  Text(
                    'Preview · not a verified result',
                    textAlign: TextAlign.center,
                    style: ShowdType.caption.copyWith(
                      color: ShowdColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ShowdSpace.gutter),
            child: ShowdButton(
              label: 'Tomorrow, then',
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _released(AppController app, Attempt a, Commitment c) {
    const ink = ShowdColors.ink;
    final soft = ink.withValues(alpha: .72);
    final source = a.evidence?['sourceLabel'] ?? a.evidence?['source'];
    final reaches = app.reachesFor(a.id);
    final held = c.restrictions.enabled && c.restrictions.packages.isNotEmpty
        ? c.restrictions.packages.first
        : null;
    final heldName = held == null ? null : appNames[held];
    final offer = app.ladderOffer(c.id);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: ShowdColors.accent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ScreenHeader(
                  leading: ShowdIconButton(
                    icon: ShowdIcons.close,
                    semanticLabel: 'Close',
                    color: ink,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  trailing: ShowdIconButton(
                    icon: ShowdIcons.share,
                    semanticLabel: 'Share proof',
                    color: ink,
                    onPressed: busy
                        ? null
                        : () => run(() => _share(c, a, app.preview)),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShowdSpace.gutter,
                  ),
                  child: RepaintBoundary(
                    key: cardKey,
                    child: Container(
                      color: ShowdColors.accent,
                      padding: const EdgeInsets.symmetric(
                        vertical: ShowdSpace.s8,
                      ),
                      child: Column(
                        children: [
                          FlippingMark(
                            showedUp: released,
                            size: 150,
                            lineColor: ink,
                            dotColor: ink,
                          ),
                          const SizedBox(height: ShowdSpace.s8),
                          Text(
                            key: ShowdKeys.attemptOutcome(a.state),
                            'Showed up.',
                            textAlign: TextAlign.center,
                            style: ShowdType.hero.copyWith(color: ink),
                          ),
                          const SizedBox(height: ShowdSpace.s3),
                          Text(
                            c.title,
                            textAlign: TextAlign.center,
                            style: ShowdType.titleM.copyWith(color: ink),
                          ),
                          const SizedBox(height: ShowdSpace.s2),
                          Text(
                            [
                              DateFormat(
                                'EEE d MMM',
                              ).format(DateTime.parse(a.date)),
                              if (a.completedAt != null) hhmm(a.completedAt!),
                              if (source != null) 'checked by $source',
                            ].join(' · '),
                            textAlign: TextAlign.center,
                            style: ShowdType.bodyM.copyWith(color: soft),
                          ),
                          if (reaches > 0) ...[
                            const SizedBox(height: ShowdSpace.s4),
                            Text(
                              'You reached for ${heldName ?? 'it'} $reaches time${reaches == 1 ? '' : 's'} and still showed up.',
                              textAlign: TextAlign.center,
                              style: ShowdType.bodyL.copyWith(color: ink),
                            ),
                          ],
                          if (app.preview) ...[
                            const SizedBox(height: ShowdSpace.s2),
                            Text(
                              'Preview · not a verified result',
                              style: ShowdType.caption.copyWith(color: ink),
                            ),
                          ],
                          const SizedBox(height: ShowdSpace.s8),
                          Wordmark(size: 22, color: ink, dotColor: ink),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShowdSpace.gutter,
                  0,
                  ShowdSpace.gutter,
                  ShowdSpace.s4,
                ),
                child: Column(
                  children: [
                    if (localError != null) ShowdNotice(localError!),
                    if (offer != null && offer.up) ...[
                      _LadderCard(
                        text:
                            'Six of your last seven. Ready for ${offer.change}?',
                        accept: 'Make it ${offer.change}',
                        onAccept: () => run(() => app.acceptLadder(offer)),
                        onDismiss: () => app.dismissLadder(c.id),
                      ),
                      const SizedBox(height: ShowdSpace.s3),
                    ],
                    if (held != null) ...[
                      ShowdButton(
                        label: 'Open ${heldName ?? 'your app'}',
                        tone: ShowdButtonTone.onAccent,
                        onPressed: () => run(() async {
                          if (!await BlockerChannel.openApp(held)) {
                            throw StateError('That app couldn’t be opened.');
                          }
                        }),
                      ),
                      const SizedBox(height: ShowdSpace.s2),
                    ],
                    ShowdButton(
                      label: 'Share proof',
                      icon: ShowdIcons.share,
                      tone: held == null
                          ? ShowdButtonTone.onAccent
                          : ShowdButtonTone.quiet,
                      busy: busy,
                      onPressed: () => run(() => _share(c, a, app.preview)),
                    ),
                    const SizedBox(height: ShowdSpace.s2),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _proofSheet(Attempt a, Commitment c) => showShowdSheet<void>(
    context,
    builder: (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it’s proven', style: ShowdType.titleL),
        const SizedBox(height: ShowdSpace.s3),
        Text(proofDescription(c), style: ShowdType.bodyL),
        const SizedBox(height: ShowdSpace.s6),
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.calendar),
          title: '${c.schedule.windowStartLocal}–${c.schedule.windowEndLocal}',
          subtitle:
              '${daysLabel(c.schedule.daysOfWeek)} · ${c.schedule.timezone}',
        ),
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.snooze),
          title: 'Every ${c.reminder.intervalMinutes} minutes',
          subtitle:
              'Up to ${c.reminder.maxReminders} reminders · ${c.reminder.volumeMode == VolumeMode.loud ? 'loud' : 'your alarm volume'}',
        ),
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.end),
          title: 'You always have an exit',
          subtitle:
              'Hold to end today. It stops reminders and gives no points.',
        ),
      ],
    ),
  );

  Future<void> _share(Commitment c, Attempt a, bool preview) async {
    final boundary =
        cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/showdup-${a.id}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        text: '${preview ? 'Preview: ' : ''}Showed up: ${c.title}. #ShowdUp',
        files: [XFile(file.path)],
      ),
    );
  }
}

class _LadderCard extends StatelessWidget {
  const _LadderCard({
    required this.text,
    required this.accept,
    required this.onAccept,
    required this.onDismiss,
  });

  final String text;
  final String accept;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
    decoration: BoxDecoration(
      color: ShowdColors.ink.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(ShowdRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: ShowdType.bodyL.copyWith(color: ShowdColors.ink)),
        Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: ShowdColors.ink),
              onPressed: onAccept,
              child: Text(accept),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: ShowdColors.ink),
              onPressed: onDismiss,
              child: const Text('Not yet'),
            ),
          ],
        ),
      ],
    ),
  );
}
