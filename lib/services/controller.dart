import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/commitment.dart';
import '../models/attempt.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../platform/alarm_channel.dart';
import '../platform/blocker_channel.dart';
import '../platform/overlay_channel.dart';
import '../core/features.dart';
import '../models/pet.dart';
import '../verification/verifier.dart';
import '../verification/verifier_registry.dart';
import 'ladder_policy.dart';
import 'repository.dart';
import 'social_service.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository) {
    _subs.add(
      repository.commitments().listen((v) {
        commitments = v;
        loading = false;
        _configure();
        _syncOverlay();
        notifyListeners();
      }, onError: _error),
    );
    _subs.add(
      repository.attempts().listen((v) {
        attempts = v;
        _reconcile();
        _syncRestrictions();
        _syncOverlay();
        _syncSocialOutcomes();
        notifyListeners();
      }, onError: _error),
    );
    _subs.add(
      repository.profile().listen((v) {
        user = v;
        _syncRestrictions();
        _syncOverlay();
        notifyListeners();
      }, onError: _error),
    );
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      // The device owns attempt rollover in local-first mode. Firebase-backed
      // sessions must not poll a cloud function while the app is open.
      if (repository is LocalRepository) unawaited(refresh());
      _reconcile();
      _syncOverlay();
      notifyListeners();
    });
    refresh();
  }
  final Repository repository;
  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, Verifier> _verifiers = {};
  final Map<String, StreamSubscription<VerificationSignal>> _signals = {};
  final Map<String, double> progress = {};
  final Map<String, String> failures = {};
  final Set<String> _submitting = {};
  Timer? _timer;
  List<Commitment> commitments = [];
  List<Attempt> attempts = [];
  AppUser? user;
  bool loading = true;
  String? error;
  bool get preview => repository.isPreview;
  void _error(Object e) {
    error = friendlyError(e);
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      if (repository is LocalRepository) {
        await _activateReadyDrafts(repository as LocalRepository);
        await _recoverNativeCompletions(repository as LocalRepository);
        await _recoverNativeFailures(repository as LocalRepository);
        await _recoverNativeReminderCounts(repository as LocalRepository);
        await _recoverNativeExpirations(repository as LocalRepository);
        await _recoverReaches(repository as LocalRepository);
      }
      await repository.call('syncAttempts', {});
      error = null;
    } catch (e) {
      _error(e);
    }
    notifyListeners();
  }

  Future<void> _activateReadyDrafts(LocalRepository local) async {
    final drafts = commitments
        .where((item) => item.status == CommitmentStatus.draft)
        .toList();
    if (drafts.isEmpty) return;
    try {
      final alarms = await AlarmChannel.getPermissionStatus();
      if (!alarms.notifications || !alarms.exactAlarm) return;
      for (final commitment in drafts) {
        final verifier = VerifierRegistry().create(commitment.verifierType);
        final available = await verifier.checkAvailability(
          commitment.verifierConfig,
        );
        if (!available.available) continue;
        try {
          await local.update(commitment.id, {
            'status': CommitmentStatus.active.wire,
          });
        } on StateError {
          // The free active-commitment limit may leave additional drafts waiting.
          return;
        }
      }
    } on MissingPluginException {
      // Non-Android tests do not expose native permissions.
    }
  }

  Future<void> _recoverNativeExpirations(LocalRepository repository) async {
    final raw = await const MethodChannel(
      'app.showdup/alarm',
    ).invokeMethod<Map>('pendingExpirations');
    if (raw == null || raw.isEmpty) return;
    final acknowledged = <String>[];
    for (final entry in raw.entries) {
      if (await repository.recordNativeExpiration(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      )) {
        acknowledged.add(entry.key);
      }
    }
    if (acknowledged.isNotEmpty) {
      await const MethodChannel(
        'app.showdup/alarm',
      ).invokeMethod('acknowledgeExpirations', {'attemptIds': acknowledged});
    }
  }

  Future<void> _recoverReaches(LocalRepository local) async {
    try {
      final counts = await BlockerChannel.reaches();
      if (counts.isNotEmpty) await local.recordReaches(counts);
    } on MissingPluginException {
      // Tests and previews have no blocker.
    } on PlatformException {
      // Older native builds do not count reaches yet.
    }
  }

  LocalRepository? get _local =>
      repository is LocalRepository ? repository as LocalRepository : null;

  /// Times the held app was opened during [attemptId].
  int reachesFor(String attemptId) => _local?.reachesFor(attemptId) ?? 0;

  /// Rest days saved, or null when rest days are off.
  int? get restBanked => _local?.restDays == true ? _local!.rest.banked : null;

  Future<bool> planRest(String date) async {
    final local = _local;
    if (local == null) return false;
    final planned = await local.planRest(date);
    if (planned) await _configure();
    notifyListeners();
    return planned;
  }

  /// A right-size offer for [commitmentId], if its recent record suggests one.
  LadderOffer? ladderOffer(String commitmentId) {
    final local = _local;
    final owner = commitment(commitmentId);
    if (!Features.ladder || local == null || owner == null) return null;
    if (owner.status != CommitmentStatus.active ||
        local.ladderHidden(commitmentId)) {
      return null;
    }
    return LadderPolicy.offer(
      owner,
      attempts,
      targetSinceMs: local.targetSinceMs(commitmentId),
    );
  }

  Future<void> acceptLadder(LadderOffer offer) => repository.update(
    offer.commitmentId,
    {'verifierConfig': offer.config.toJson(), 'title': offer.title},
  );

  Future<void> dismissLadder(String commitmentId) async {
    await _local?.dismissLadder(commitmentId);
    notifyListeners();
  }

  PetSnapshot get petSnapshot {
    final local = repository is LocalRepository
        ? repository as LocalRepository
        : null;
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekly = attempts
        .where((a) => !a.windowEndAt.isBefore(monday))
        .toList();
    final recent = attempts
        .where(
          (a) => a.windowEndAt.isAfter(now.subtract(const Duration(days: 7))),
        )
        .toList();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final today = attempts.where((a) => a.date == todayKey).toList();
    final active = attempts
        .where((a) => a.state == AttemptState.pending && a.isWindowOpen)
        .firstOrNull;
    final currentSnoozes = active?.snoozes ?? 0;
    final social = SocialService.instance;
    final myUid = social.user?.uid;
    final myScore = social.latestScores
        .where((item) => item.uid == myUid)
        .firstOrNull;
    return PetSnapshot(
      mascot: local?.selectedMascot ?? MascotId.dot,
      mood: PetScoring.mood(
        recentAttempts: recent,
        currentSnoozes: currentSnoozes,
      ),
      weeklyScore: PetScoring.normalizedScore(weekly),
      todayCompleted: today
          .where((a) => a.state == AttemptState.completed)
          .length,
      todayTotal: today.length,
      streak: user?.stats.currentStreak ?? 0,
      consecutiveMisses: PetScoring.consecutiveMisses(attempts),
      burstCount: 0,
      activeAttemptId: active?.id,
      activeTitle: active == null
          ? null
          : commitment(active.commitmentId)?.title,
      rank: myScore?.rank,
      friendGlyphs: social.latestScores
          .where((item) => item.uid != myUid)
          .take(3)
          .map((item) => MascotId.fromWire(item.mascot).fallbackGlyph)
          .toList(),
      topRanks: social.latestScores
          .take(5)
          .map(
            (item) => {
              'rank': item.rank,
              'name': item.displayName,
              'score': item.score,
            },
          )
          .toList(),
    );
  }

  Future<void> _syncSocialOutcomes() async {
    final local = repository;
    if (local is! LocalRepository || !SocialService.instance.googleLinked) {
      return;
    }
    final terminal = attempts.where((attempt) {
      final now = DateTime.now();
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      return attempt.state.isTerminal && !attempt.windowEndAt.isBefore(monday);
    }).toList()..sort((a, b) => a.windowEndAt.compareTo(b.windowEndAt));
    for (final attempt in terminal) {
      if (local.isSocialOutcomeSynced(attempt.id)) continue;
      try {
        if (await SocialService.instance.syncOutcome(attempt, petSnapshot)) {
          await local.markSocialOutcomeSynced(attempt.id);
        }
      } catch (_) {
        // Retry on the next repository update; local completion remains valid.
        return;
      }
    }
  }

  Future<void> setMascot(MascotId mascot) async {
    final local = repository;
    if (local is LocalRepository) await local.setMascot(mascot);
    await _syncOverlay();
    notifyListeners();
  }

  Future<void> _syncOverlay() async {
    if (preview || repository is! LocalRepository) return;
    try {
      await OverlayChannel.sync(petSnapshot);
    } on MissingPluginException {
      // Overlay is Android-only.
    } on PlatformException {
      // Revoked overlay permission must not make the app unusable.
    }
  }

  Future<void> _recoverNativeCompletions(LocalRepository repository) async {
    final raw = await const MethodChannel(
      'app.showdup/alarm',
    ).invokeMethod<Map>('pendingCompletions');
    if (raw == null || raw.isEmpty) return;
    final acknowledged = <String>[];
    for (final entry in raw.entries) {
      final saved = await repository.recordNativeCompletion(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (saved) acknowledged.add(entry.key);
    }
    if (acknowledged.isNotEmpty) {
      await const MethodChannel(
        'app.showdup/alarm',
      ).invokeMethod('acknowledgeCompletions', {'attemptIds': acknowledged});
    }
  }

  Future<void> _recoverNativeReminderCounts(LocalRepository repository) async {
    final raw = await const MethodChannel(
      'app.showdup/alarm',
    ).invokeMethod<Map>('pendingReminderEvents');
    if (raw == null) return;
    final counts = Map<String, dynamic>.from(
      raw['counts'] as Map? ?? const <String, dynamic>{},
    );
    await repository.recordReminderCounts(counts);

    // Individual events are useful only until their durable cumulative count
    // has been merged. Removing them bounds native storage while the counts
    // remain available for idempotent recovery after a crash.
    final events = Map<String, dynamic>.from(
      raw['events'] as Map? ?? const <String, dynamic>{},
    );
    if (events.isNotEmpty) {
      await const MethodChannel('app.showdup/alarm').invokeMethod(
        'acknowledgeReminderEvents',
        {'eventIds': events.keys.toList()},
      );
    }
  }

  Future<void> _recoverNativeFailures(LocalRepository repository) async {
    final raw = await const MethodChannel(
      'app.showdup/alarm',
    ).invokeMethod<Map>('pendingFailures');
    if (raw == null || raw.isEmpty) return;
    final acknowledged = <String>[];
    for (final entry in raw.entries) {
      final saved = await repository.recordNativeFailure(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (saved) acknowledged.add(entry.key);
    }
    if (acknowledged.isNotEmpty) {
      await const MethodChannel(
        'app.showdup/alarm',
      ).invokeMethod('acknowledgeFailures', {'attemptIds': acknowledged});
    }
  }

  Commitment? commitment(String id) {
    for (final c in commitments) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _configure() async {
    if (preview) return;
    try {
      await const MethodChannel('app.showdup/alarm').invokeMethod(
        'configureCommitments',
        {
          'commitments': commitments
              .where((c) => c.status == CommitmentStatus.active)
              .map(
                (c) => {
                  'id': c.id,
                  ...c.toJson(),
                  // Native alarms skip planned rest days.
                  'skipDates': _local?.plannedRestDates ?? const <String>[],
                },
              )
              .toList(),
        },
      );
      await _syncRestrictions();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _syncRestrictions() async {
    if (preview) return;
    final sessions = <BlockerSession>[];
    final isPro = user?.isPro == true;
    // Pro holds every chosen app. Free holds one app on one alarm once the
    // catch ships; native code applies the same clamp.
    if (isPro || Features.catchEnabled) {
      final open =
          attempts
              .where((a) => a.state == AttemptState.pending && a.isWindowOpen)
              .toList()
            ..sort((a, b) => a.windowStartAt.compareTo(b.windowStartAt));
      for (final attempt in open) {
        final owner = commitment(attempt.commitmentId);
        if (owner == null || !owner.restrictions.enabled) continue;
        final packages = owner.restrictions.packages
            .where((package) => !Restrictions.neverBlock.contains(package))
            .toList();
        if (packages.isEmpty) continue;
        sessions.add(
          BlockerSession(
            attemptId: attempt.id,
            commitmentId: attempt.commitmentId,
            packages: isPro ? packages : packages.take(1).toList(),
            activeFromEpochMs: attempt.windowStartAt.millisecondsSinceEpoch,
            activeUntilEpochMs: attempt.windowEndAt.millisecondsSinceEpoch,
          ),
        );
        if (!isPro) break;
      }
    }
    try {
      await BlockerChannel.sync(sessions);
    } on MissingPluginException {
      // Unit tests and non-Android previews do not provide this channel.
    }
  }

  Future<void> _reconcile() async {
    for (final a in attempts) {
      if (a.state.isTerminal || DateTime.now().isAfter(a.windowEndAt)) {
        await stop(a);
      }
    }
  }

  Future<void> start(Attempt a) async {
    if (preview) {
      progress[a.id] = .64;
      notifyListeners();
      return;
    }
    if (_verifiers.containsKey(a.id) || !a.isWindowOpen) return;
    final c = commitment(a.commitmentId);
    if (c == null) return;
    final verifier = VerifierRegistry().create(c.verifierType);
    final available = await verifier.checkAvailability(c.verifierConfig);
    if (!available.available) {
      failures[a.id] =
          available.reason ?? 'Allow the required permission to continue.';
      notifyListeners();
      return;
    }
    failures.remove(a.id);
    _verifiers[a.id] = verifier;
    _signals[a.id] = verifier.signals().listen(
      (s) async {
        progress[a.id] = s.progress;
        if (s.outcome == Outcome.unverifiable) {
          failures[a.id] = s.failureReason ?? 'Sensor unavailable';
          await stop(a);
        } else if (s.outcome == Outcome.satisfied) {
          if (_submitting.add(a.id)) {
            try {
              await repository.call('submitEvidence', {
                'commitmentId': a.commitmentId,
                'date': a.date,
                'type': c.verifierType.wire,
                'payload': s.evidence,
              });
              await stop(a);
              error = null;
            } catch (e) {
              failures[a.id] = friendlyError(e);
              _submitting.remove(a.id);
              // Native tracking retains progress and retries while the window is open.
            }
          }
        }
        notifyListeners();
      },
      onError: (Object e) {
        failures[a.id] = friendlyError(e);
        notifyListeners();
      },
    );
    try {
      await verifier.arm(a, c.verifierConfig);
    } catch (e) {
      failures[a.id] = friendlyError(e);
      await stop(a);
    }
    notifyListeners();
  }

  Future<void> stop(Attempt a) async {
    await _signals.remove(a.id)?.cancel();
    await _verifiers.remove(a.id)?.disarm();
    if (!preview && a.state.isTerminal) {
      await AlarmChannel.cancelReminders(a.id);
    }
  }

  /// Ends today. With [rest], a saved rest day covers it instead.
  Future<void> end(Attempt a, {bool rest = false}) async {
    if (!preview) {
      await const MethodChannel(
        'app.showdup/alarm',
      ).invokeMethod('silence', {'attemptId': a.id});
      await AlarmChannel.cancelReminders(a.id);
    }
    await stop(a);
    await repository.call('endAttempt', {
      'commitmentId': a.commitmentId,
      'date': a.date,
      'reason': 'user_ended',
      if (rest) 'rest': true,
    });
  }

  Future<void> unable(Attempt a) async {
    await stop(a);
    await repository.call('reportVerifierFailure', {
      'commitmentId': a.commitmentId,
      'date': a.date,
      'reason': 'sensor_lost',
    });
  }

  Future<void> snooze(Attempt a) async {
    if (!preview) {
      await const MethodChannel(
        'app.showdup/alarm',
      ).invokeMethod('silence', {'attemptId': a.id});
    }
  }

  Future<void> shutdown() async {
    _timer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    for (final a in attempts) {
      await stop(a);
    }
    if (!preview) {
      await BlockerChannel.stop();
      await const MethodChannel('app.showdup/alarm').invokeMethod('stopAll');
    }
    await repository.close();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    for (final s in _signals.values) {
      s.cancel();
    }
    super.dispose();
  }
}

String friendlyError(Object e) {
  var message = e.toString().replaceFirst('Bad state: ', '');
  if (message.contains('unavailable') ||
      message.contains('network-request-failed')) {
    return 'You’re offline. Reconnect to sync and verify completion.';
  }
  if (message.contains('wrong-password') ||
      message.contains('invalid-credential')) {
    return 'Email or password is incorrect.';
  }
  if (message.contains('email-already-in-use')) {
    return 'This email already has an account. Sign in instead.';
  }
  return message.replaceAll(RegExp(r'\[[^\]]+\]\s*'), '');
}
