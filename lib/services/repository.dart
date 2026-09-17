import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/commitment.dart';
import '../models/attempt.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../core/scheduling.dart';
import '../models/pet.dart';

abstract class Repository {
  bool get isPreview;
  Stream<List<Commitment>> commitments();
  Stream<List<Attempt>> attempts();
  Stream<AppUser> profile();
  Future<void> create(Map<String, dynamic> data);
  Future<void> update(String id, Map<String, dynamic> patch);
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data);
  Future<void> close();
}

/// The normal on-device repository.  It deliberately keeps reminders and
/// evidence collection on the phone; Firebase is an optional future backup,
/// not a dependency for using the product.
class LocalRepository implements Repository {
  LocalRepository(this.prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _load();
  }

  static const _storageKey = 'localRepository.v1';
  static const _uidKey = 'localRepository.uid';
  final SharedPreferences prefs;
  final DateTime Function() _clock;
  final _changes = StreamController<void>.broadcast();
  final _random = Random.secure();
  Future<void> _mutation = Future.value();
  late final String _uid;
  List<Commitment> _commitments = [];
  List<Attempt> _attempts = [];
  final Map<String, int> _effectiveFromMs = {};
  final Set<String> _pauseWhenIdle = {};
  final Set<String> _simplifyScheduleWhenIdle = {};
  int? _lastRolloverMs;
  late AppUser _profile;
  MascotId _selectedMascot = MascotId.dot;
  bool _petCracked = false;
  int _burstCount = 0;
  int? _crackedAtMs;
  List<int> _burstEventsMs = [];

  /// Serializes writes so a billing update, native-completion recovery and UI
  /// action cannot overwrite each other's SharedPreferences snapshot.
  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _mutation.then((_) => operation());
    _mutation = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  bool get isPreview => false;

  void _load() {
    _uid = prefs.getString(_uidKey) ?? _newId('device');
    if (!prefs.containsKey(_uidKey)) prefs.setString(_uidKey, _uid);
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        _commitments = (data['commitments'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((e) => Commitment.fromJson(e.remove('id') as String, e))
            .toList();
        _attempts = (data['attempts'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((e) => Attempt.fromJson(e.remove('id') as String, e))
            .toList();
        final effective = Map<String, dynamic>.from(
          data['effectiveFromMs'] as Map? ?? const <String, dynamic>{},
        );
        for (final commitment in _commitments) {
          // Migration: old local installs must not suddenly receive a backlog
          // of failures when upgrading to catch-up rollover.
          _effectiveFromMs[commitment.id] =
              (effective[commitment.id] as num?)?.toInt() ??
              _clock().millisecondsSinceEpoch;
        }
        _pauseWhenIdle.addAll(
          (data['pauseWhenIdle'] as List? ?? const <dynamic>[])
              .whereType<String>(),
        );
        _simplifyScheduleWhenIdle.addAll(
          (data['simplifyScheduleWhenIdle'] as List? ?? const <dynamic>[])
              .whereType<String>(),
        );
        _lastRolloverMs =
            (data['lastRolloverMs'] as num?)?.toInt() ??
            _clock().millisecondsSinceEpoch;
        _profile = AppUser.fromJson(
          _uid,
          Map<String, dynamic>.from(data['profile'] as Map? ?? {}),
        );
        _selectedMascot = MascotId.fromWire(data['selectedMascot'] as String?);
        _petCracked = data['petCracked'] == true;
        _burstCount = (data['burstCount'] as num?)?.toInt() ?? 0;
        _crackedAtMs = (data['crackedAtMs'] as num?)?.toInt();
        _burstEventsMs = (data['burstEventsMs'] as List? ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList();
        return;
      } catch (_) {
        // A corrupt local cache must not prevent the user opening the app.
      }
    }
    _profile = AppUser(uid: _uid, displayName: 'You', timezone: 'Asia/Kolkata');
  }

  String _newId(String prefix) =>
      '$prefix-${_clock().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<void> _save({bool notify = true}) async {
    _updatePetState();
    _trimHistory();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'profile': {
          ..._profile.toClientWritableJson(),
          'isPro': _profile.isPro,
          'stats': _profileWithStats.stats.toJson(),
        },
        'commitments': _commitments
            .map((c) => <String, dynamic>{'id': c.id, ...c.toJson()})
            .toList(),
        'attempts': _attempts
            .map((a) => <String, dynamic>{'id': a.id, ...a.toJson()})
            .toList(),
        'effectiveFromMs': _effectiveFromMs,
        'pauseWhenIdle': _pauseWhenIdle.toList(),
        'simplifyScheduleWhenIdle': _simplifyScheduleWhenIdle.toList(),
        'lastRolloverMs': _lastRolloverMs,
        'selectedMascot': _selectedMascot.wire,
        'petCracked': _petCracked,
        'burstCount': _burstCount,
        'crackedAtMs': _crackedAtMs,
        'burstEventsMs': _burstEventsMs,
      }),
    );
    if (notify && !_changes.isClosed) _changes.add(null);
  }

  /// Animals are a Pro unlock. The stored choice survives a lapsed
  /// subscription and comes back on renewal; until then the dot shows.
  MascotId get selectedMascot =>
      _selectedMascot.isPremium && !_profile.isPro ? MascotId.dot : _selectedMascot;
  bool get petCracked => _petCracked;
  int get burstCount => _burstCount;
  int weeklyPetPenalty(DateTime monday) =>
      _burstEventsMs
          .where((stamp) => stamp >= monday.millisecondsSinceEpoch)
          .length *
      100;

  Future<void> setMascot(MascotId mascot) => _exclusive(() async {
    if (mascot.isPremium && !_profile.isPro) {
      throw StateError('Animal companions unlock with ShowdUp Pro.');
    }
    _selectedMascot = mascot;
    await _save();
  });

  bool isSocialOutcomeSynced(String attemptId) =>
      prefs.getBool('social.outcome.$attemptId') == true;

  Future<void> markSocialOutcomeSynced(String attemptId) =>
      prefs.setBool('social.outcome.$attemptId', true);

  void _updatePetState() {
    final misses = PetScoring.consecutiveMisses(_attempts);
    if (!_petCracked && misses >= 3) {
      _petCracked = true;
      _burstCount++;
      _crackedAtMs = _clock().millisecondsSinceEpoch;
      _burstEventsMs.add(_crackedAtMs!);
    }
    if (_petCracked && _crackedAtMs != null) {
      final recovered = _attempts.any(
        (a) =>
            a.state == AttemptState.completed &&
            a.completedAt != null &&
            a.completedAt!.millisecondsSinceEpoch > _crackedAtMs!,
      );
      if (recovered) {
        _petCracked = false;
        _crackedAtMs = null;
      }
    }
  }

  Future<bool> recordNativeExpiration(
    String attemptId,
    Map<String, dynamic> expiration,
  ) => _exclusive(() async {
    final index = _attempts.indexWhere((attempt) => attempt.id == attemptId);
    if (index < 0 || _attempts[index].state.isTerminal) return index >= 0;
    _attempts[index] = _attemptWith(
      _attempts[index],
      state: AttemptState.expired,
      endedReason: EndedReason.windowExpired,
      evidence: {
        'reason': expiration['reason'] ?? 'reminder_limit',
        'expiredAt': expiration['expiredAt'],
      },
    );
    await _save();
    return true;
  });

  /// Keep local preferences bounded while preserving all unfinished work and
  /// every completed attempt from the most recent two years. A count limit
  /// would silently shorten Pro history for users with multiple commitments.
  void _trimHistory() {
    final cutoff = _clock().subtract(const Duration(days: 730));
    _attempts = _attempts
        .where(
          (attempt) =>
              !attempt.state.isTerminal ||
              !attempt.windowEndAt.isBefore(cutoff),
        )
        .toList();
  }

  String _dateFor(DateTime instant, CommitmentSchedule schedule) {
    final local = tz.TZDateTime.from(
      instant,
      tz.getLocation(schedule.timezone),
    );
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Commitment _withoutCustomSchedule(Commitment commitment) =>
      Commitment.fromJson(commitment.id, {
        ...commitment.toJson(),
        'schedule': CommitmentSchedule(
          daysOfWeek: commitment.schedule.daysOfWeek,
          windowStartLocal: commitment.schedule.windowStartLocal,
          windowEndLocal: commitment.schedule.windowEndLocal,
          timezone: commitment.schedule.timezone,
        ).toJson(),
      });

  /// Replays a bounded set of missed scheduled days after a restart. Attempts
  /// are generated only after the commitment became effective, so adding or
  /// resuming a commitment after its window cannot create a retroactive loss.
  bool _rollover() {
    final now = _clock();
    var changed = false;
    _attempts = _attempts.map((attempt) {
      if (attempt.state == AttemptState.pending &&
          now.isAfter(attempt.windowEndAt)) {
        changed = true;
        return _attemptWith(
          attempt,
          state: AttemptState.expired,
          endedReason: EndedReason.windowExpired,
        );
      }
      return attempt;
    }).toList();
    for (final commitmentId in _pauseWhenIdle.toList()) {
      final stillPending = _attempts.any(
        (attempt) =>
            attempt.commitmentId == commitmentId &&
            attempt.state == AttemptState.pending,
      );
      if (stillPending) continue;
      _commitments = _commitments
          .map(
            (commitment) => commitment.id == commitmentId
                ? Commitment.fromJson(commitment.id, {
                    ...commitment.toJson(),
                    'status': CommitmentStatus.paused.wire,
                  })
                : commitment,
          )
          .toList();
      _pauseWhenIdle.remove(commitmentId);
      changed = true;
    }
    for (final commitmentId in _simplifyScheduleWhenIdle.toList()) {
      final stillPending = _attempts.any(
        (attempt) =>
            attempt.commitmentId == commitmentId &&
            attempt.state == AttemptState.pending,
      );
      if (stillPending) continue;
      _commitments = _commitments
          .map(
            (commitment) => commitment.id == commitmentId
                ? _withoutCustomSchedule(commitment)
                : commitment,
          )
          .toList();
      _simplifyScheduleWhenIdle.remove(commitmentId);
      changed = true;
    }
    final byId = <String, Attempt>{for (final a in _attempts) a.id: a};
    for (final commitment in _commitments) {
      if (commitment.status != CommitmentStatus.active) continue;
      final zone = tz.getLocation(commitment.schedule.timezone);
      final localNow = tz.TZDateTime.from(now, zone);
      final effective = DateTime.fromMillisecondsSinceEpoch(
        _effectiveFromMs[commitment.id] ?? now.millisecondsSinceEpoch,
      );
      final since = DateTime.fromMillisecondsSinceEpoch(
        max(
          _lastRolloverMs ?? effective.millisecondsSinceEpoch,
          effective.millisecondsSinceEpoch,
        ),
      );
      final localSince = tz.TZDateTime.from(since, zone);
      // Match the two-year retained history while preventing a corrupt or
      // very old clock from making launch perform unbounded work.
      final first = DateTime(
        localNow.year,
        localNow.month,
        localNow.day,
      ).subtract(const Duration(days: 730));
      var day = DateTime(localSince.year, localSince.month, localSince.day);
      if (day.isBefore(first)) day = first;
      final today = DateTime(localNow.year, localNow.month, localNow.day);
      while (!day.isAfter(today)) {
        if (commitment.schedule.daysOfWeek.contains(day.weekday)) {
          final window = resolveWindow(commitment.schedule, day);
          final date = _dateFor(window.start, commitment.schedule);
          final id = '${commitment.id}_$date';
          if (!byId.containsKey(id) &&
              !effective.isAfter(window.end) &&
              now.isAfter(window.start)) {
            final expired = now.isAfter(window.end);
            final created = Attempt(
              id: id,
              commitmentId: commitment.id,
              ownerUid: _uid,
              date: date,
              windowStartAt: window.start,
              windowEndAt: window.end,
              state: expired ? AttemptState.expired : AttemptState.pending,
              endedReason: expired ? EndedReason.windowExpired : null,
            );
            _attempts.add(created);
            byId[id] = created;
            changed = true;
          }
        }
        day = day.add(const Duration(days: 1));
      }
    }
    _lastRolloverMs = now.millisecondsSinceEpoch;
    return changed;
  }

  Attempt _attemptWith(
    Attempt attempt, {
    required AttemptState state,
    EndedReason? endedReason,
    Map<String, dynamic>? evidence,
    DateTime? completedAt,
    int? remindersFired,
    int? snoozes,
  }) => Attempt.fromJson(attempt.id, {
    ...attempt.toJson(),
    'state': state.wire,
    ..._intJson('remindersFired', remindersFired),
    ..._intJson('snoozes', snoozes),
    ..._endedReasonJson(endedReason),
    ..._evidenceJson(evidence),
    if (completedAt case final stamp?)
      'completedAt': stamp.toUtc().toIso8601String(),
  });

  Map<String, String> _endedReasonJson(EndedReason? reason) =>
      reason == null ? const {} : {'endedReason': reason.wire};

  Map<String, Map<String, dynamic>> _evidenceJson(
    Map<String, dynamic>? value,
  ) => value == null ? const {} : {'evidence': value};

  Map<String, int> _intJson(String key, int? value) =>
      value == null ? const {} : {key: value};

  Attempt _pendingAttempt(Map<String, dynamic> data) {
    final id = '${data['commitmentId']}_${data['date']}';
    return _attempts.firstWhere(
      (a) => a.id == id,
      orElse: () =>
          throw StateError('No active attempt found for this commitment.'),
    );
  }

  bool _isWindowOpen(Attempt attempt, DateTime instant) =>
      instant.isAfter(attempt.windowStartAt) &&
      instant.isBefore(attempt.windowEndAt);

  @override
  Stream<List<Commitment>> commitments() async* {
    yield List.unmodifiable(_commitments);
    yield* _changes.stream.map((_) => List.unmodifiable(_commitments));
  }

  @override
  Stream<List<Attempt>> attempts() async* {
    yield List.unmodifiable(_attempts);
    yield* _changes.stream.map((_) => List.unmodifiable(_attempts));
  }

  AppUser get _profileWithStats {
    final finished = _attempts.where((a) => a.state.isTerminal).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    var streak = 0;
    for (final attempt in finished) {
      if (attempt.state == AttemptState.completed) {
        streak++;
      } else if (attempt.state.breaksStreak) {
        break;
      }
    }
    final completed = _attempts
        .where((a) => a.state == AttemptState.completed)
        .length;
    final abandoned = _attempts
        .where((a) => a.state == AttemptState.abandoned)
        .length;
    final unverifiable = _attempts
        .where((a) => a.state == AttemptState.unverifiable)
        .length;
    return AppUser.fromJson(_uid, {
      ..._profile.toClientWritableJson(),
      'isPro': _profile.isPro,
      'stats': {
        'currentStreak': streak,
        // Retaining the previous maximum avoids shrinking it between sessions.
        'longestStreak': max(_profile.stats.longestStreak, streak),
        'completed': completed,
        'abandoned': abandoned,
        'unverifiable': unverifiable,
      },
    });
  }

  @override
  Stream<AppUser> profile() async* {
    yield _profileWithStats;
    yield* _changes.stream.map((_) => _profileWithStats);
  }

  @override
  Future<void> create(Map<String, dynamic> data) => _exclusive(() async {
    _rollover();
    final requestedStatus = CommitmentStatus.from(
      data['status'] as String? ?? CommitmentStatus.active.wire,
    );
    if (requestedStatus == CommitmentStatus.active &&
        _commitments.where((c) => c.status == CommitmentStatus.active).length >=
            _profile.maxActiveCommitments) {
      throw StateError(
        'Free includes one active commitment. Upgrade to Pro for more.',
      );
    }
    final id = _newId('commitment');
    final commitment = Commitment.fromJson(id, {
      ...data,
      'ownerUid': _uid,
      'status': requestedStatus.wire,
    });
    final validation = commitment.validate();
    if (validation != null) throw StateError(validation);
    if (!_profile.isPro && commitment.schedule.hasCustomWindows) {
      throw StateError('Different times by day require ShowdUp Pro.');
    }
    _commitments = [..._commitments, commitment];
    if (requestedStatus == CommitmentStatus.active) {
      _effectiveFromMs[id] = _clock().millisecondsSinceEpoch;
      _rollover();
    }
    await _save();
  });

  /// Called by the billing integration after RevenueCat has refreshed the
  /// device entitlement. It is local state only; no purchase status is ever
  /// trusted from user-editable commitment data.
  Future<void> setPro(bool isPro) => _exclusive(() async {
    if (_profile.isPro == isPro) return;
    _profile = AppUser.fromJson(_uid, {
      ..._profile.toClientWritableJson(),
      'isPro': isPro,
      'stats': _profileWithStats.stats.toJson(),
    });
    if (isPro) {
      _pauseWhenIdle.clear();
      _simplifyScheduleWhenIdle.clear();
    } else {
      final active = _commitments
          .where((commitment) => commitment.status == CommitmentStatus.active)
          .toList();
      for (final commitment in active.skip(1)) {
        final hasPending = _attempts.any(
          (attempt) =>
              attempt.commitmentId == commitment.id &&
              attempt.state == AttemptState.pending,
        );
        if (hasPending) {
          _pauseWhenIdle.add(commitment.id);
        } else {
          _commitments = _commitments
              .map(
                (item) => item.id == commitment.id
                    ? Commitment.fromJson(item.id, {
                        ...item.toJson(),
                        'status': CommitmentStatus.paused.wire,
                      })
                    : item,
              )
              .toList();
        }
      }
      for (final commitment in _commitments.where(
        (item) => item.schedule.hasCustomWindows,
      )) {
        final hasPending = _attempts.any(
          (attempt) =>
              attempt.commitmentId == commitment.id &&
              attempt.state == AttemptState.pending,
        );
        if (hasPending) {
          _simplifyScheduleWhenIdle.add(commitment.id);
        } else {
          _commitments = _commitments
              .map(
                (item) => item.id == commitment.id
                    ? _withoutCustomSchedule(item)
                    : item,
              )
              .toList();
        }
      }
    }
    await _save();
  });

  /// Reconciles a completion the Android foreground service saved while
  /// Flutter was stopped. The native record is acknowledged only after this
  /// method has persisted the local attempt.
  Future<bool> recordNativeCompletion(
    String attemptId,
    Map<String, dynamic> completion,
  ) => _exclusive(() async {
    var index = _attempts.indexWhere((attempt) => attempt.id == attemptId);
    if (index < 0) {
      final separator = attemptId.lastIndexOf('_');
      if (separator < 1) return false;
      final commitmentId = attemptId.substring(0, separator);
      final date = DateTime.tryParse(attemptId.substring(separator + 1));
      final commitment = _commitments
          .where((item) => item.id == commitmentId)
          .firstOrNull;
      if (date == null || commitment == null) return true;
      final window = resolveWindow(
        commitment.schedule,
        DateTime(date.year, date.month, date.day),
      );
      _attempts.add(
        Attempt(
          id: attemptId,
          commitmentId: commitmentId,
          ownerUid: _uid,
          date: attemptId.substring(separator + 1),
          windowStartAt: window.start,
          windowEndAt: window.end,
          state: AttemptState.pending,
        ),
      );
      index = _attempts.length - 1;
    }
    if (_attempts[index].state.isTerminal) return true;
    final attempt = _attempts[index];
    _attempts[index] = _attemptWith(
      attempt,
      state: AttemptState.completed,
      endedReason: EndedReason.verified,
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        (completion['completedAt'] as num?)?.toInt() ??
            _clock().millisecondsSinceEpoch,
      ),
      evidence: Map<String, dynamic>.from(
        completion['payload'] as Map? ?? const <String, dynamic>{},
      ),
    );
    await _save();
    return true;
  });

  /// Persists a native verification failure that occurred while Flutter was
  /// stopped. It awards no completion and, like every verifier outage, does
  /// not break the user's streak.
  Future<bool> recordNativeFailure(
    String attemptId,
    Map<String, dynamic> failure,
  ) => _exclusive(() async {
    var index = _attempts.indexWhere((attempt) => attempt.id == attemptId);
    if (index < 0) {
      final separator = attemptId.lastIndexOf('_');
      if (separator < 1) return false;
      final commitmentId = attemptId.substring(0, separator);
      final date = DateTime.tryParse(attemptId.substring(separator + 1));
      final commitment = _commitments
          .where((item) => item.id == commitmentId)
          .firstOrNull;
      if (date == null || commitment == null) return false;
      final window = resolveWindow(
        commitment.schedule,
        DateTime(date.year, date.month, date.day),
      );
      _attempts.add(
        Attempt(
          id: attemptId,
          commitmentId: commitmentId,
          ownerUid: _uid,
          date: attemptId.substring(separator + 1),
          windowStartAt: window.start,
          windowEndAt: window.end,
          state: AttemptState.pending,
        ),
      );
      index = _attempts.length - 1;
    }
    if (_attempts[index].state.isTerminal) return true;
    _attempts[index] = _attemptWith(
      _attempts[index],
      state: AttemptState.unverifiable,
      endedReason: EndedReason.verifierError,
      evidence: {
        'type': failure['type'],
        'failureReason': failure['reason'] ?? 'verification_unavailable',
        'failedAt': failure['failedAt'],
      },
    );
    await _save();
    return true;
  });

  /// Applies native reminder counters after a Flutter restart. Native events
  /// are cumulative, so taking the maximum keeps retries idempotent.
  Future<bool> recordReminderCounts(Map<String, dynamic> counts) =>
      _exclusive(() async {
        var changed = false;
        for (final entry in counts.entries) {
          final separator = entry.key.lastIndexOf(':');
          if (separator < 1) continue;
          final value = (entry.value as num?)?.toInt();
          if (value == null || value < 0) continue;
          final attemptId = entry.key.substring(0, separator);
          final kind = entry.key.substring(separator + 1);
          final index = _attempts.indexWhere(
            (attempt) => attempt.id == attemptId,
          );
          if (index < 0 || (kind != 'fired' && kind != 'snoozed')) continue;
          final attempt = _attempts[index];
          final fired = kind == 'fired'
              ? max(attempt.remindersFired, value)
              : attempt.remindersFired;
          final snoozed = kind == 'snoozed'
              ? max(attempt.snoozes, value)
              : attempt.snoozes;
          if (fired == attempt.remindersFired && snoozed == attempt.snoozes) {
            continue;
          }
          _attempts[index] = _attemptWith(
            attempt,
            state: attempt.state,
            endedReason: attempt.endedReason,
            evidence: attempt.evidence,
            completedAt: attempt.completedAt,
            remindersFired: fired,
            snoozes: snoozed,
          );
          changed = true;
        }
        if (changed) await _save();
        return true;
      });

  @override
  Future<void> update(
    String id,
    Map<String, dynamic> patch,
  ) => _exclusive(() async {
    _rollover();
    final old = _commitments.where((c) => c.id == id).firstOrNull;
    if (old == null) throw StateError('Commitment not found.');
    final hasPendingAttempt = _attempts.any(
      (attempt) =>
          attempt.commitmentId == id && attempt.state == AttemptState.pending,
    );
    const materialFields = {
      'verifierType',
      'verifierConfig',
      'schedule',
      'reminder',
      'restrictions',
    };
    final oldJson = old.toJson();
    final materialChanged = materialFields.any(
      (field) =>
          patch.containsKey(field) &&
          jsonEncode(patch[field]) != jsonEncode(oldJson[field]),
    );
    if (hasPendingAttempt && materialChanged) {
      throw StateError(
        'This commitment is active right now. Edit it after today’s attempt ends.',
      );
    }
    final updated = Commitment.fromJson(id, {...old.toJson(), ...patch});
    final validation = updated.validate();
    if (validation != null) throw StateError(validation);
    final advancedScheduleChanged =
        jsonEncode(updated.schedule.toJson()) !=
        jsonEncode(old.schedule.toJson());
    if (!_profile.isPro &&
        updated.schedule.hasCustomWindows &&
        advancedScheduleChanged) {
      throw StateError('Different times by day require ShowdUp Pro.');
    }
    if (old.status != CommitmentStatus.active &&
        updated.status == CommitmentStatus.active &&
        _commitments
                .where((item) => item.status == CommitmentStatus.active)
                .length >=
            _profile.maxActiveCommitments) {
      throw StateError(
        'Free includes one active commitment. Upgrade to Pro for more.',
      );
    }
    _commitments = _commitments.map((c) => c.id == id ? updated : c).toList();
    if (updated.status != CommitmentStatus.active) {
      _attempts = _attempts
          .map(
            (a) => a.commitmentId == id && a.state == AttemptState.pending
                ? _attemptWith(
                    a,
                    state: AttemptState.abandoned,
                    endedReason: EndedReason.userEnded,
                  )
                : a,
          )
          .toList();
    } else if (old.status != CommitmentStatus.active) {
      // Resuming starts with the next eligible window, never a missed one.
      _effectiveFromMs[id] = _clock().millisecondsSinceEpoch;
    }
    _rollover();
    await _save();
  });

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) =>
      _exclusive(() async {
        final rolled = _rollover();
        if (name == 'syncAttempts') {
          if (rolled) await _save();
          return {'ok': true};
        }
        if (name == 'deleteAccount') {
          _commitments = [];
          _attempts = [];
          _effectiveFromMs.clear();
          _pauseWhenIdle.clear();
          _simplifyScheduleWhenIdle.clear();
          _lastRolloverMs = null;
          _profile = AppUser(
            uid: _uid,
            displayName: 'You',
            timezone: _profile.timezone,
          );
          _selectedMascot = MascotId.dot;
          _petCracked = false;
          _burstCount = 0;
          _crackedAtMs = null;
          _burstEventsMs = [];
          await prefs.remove(_storageKey);
          if (!_changes.isClosed) _changes.add(null);
          return {'ok': true};
        }
        final attempt = _pendingAttempt(data);
        if (attempt.state != AttemptState.pending) {
          throw StateError('This attempt has already ended.');
        }
        late Attempt replacement;
        switch (name) {
          case 'submitEvidence':
            if (!_isWindowOpen(attempt, _clock())) {
              throw StateError(
                'Evidence must be submitted during the scheduled window.',
              );
            }
            replacement = _attemptWith(
              attempt,
              state: AttemptState.completed,
              endedReason: EndedReason.verified,
              completedAt: _clock(),
              evidence: Map<String, dynamic>.from(
                data['payload'] as Map? ?? {},
              ),
            );
            break;
          case 'endAttempt':
            replacement = _attemptWith(
              attempt,
              state: AttemptState.abandoned,
              endedReason: EndedReason.userEnded,
            );
            break;
          case 'reportVerifierFailure':
            replacement = _attemptWith(
              attempt,
              state: AttemptState.unverifiable,
              endedReason: EndedReason.verifierError,
            );
            break;
          default:
            throw StateError('Unsupported local action: $name');
        }
        _attempts = _attempts
            .map((a) => a.id == attempt.id ? replacement : a)
            .toList();
        await _save();
        return {'state': replacement.state.wire};
      });

  @override
  Future<void> close() async {
    await _changes.close();
  }
}

/// An explicit, local product preview. It never claims sensor or server verification.
class PreviewRepository implements Repository {
  PreviewRepository(this.prefs) {
    _load();
  }
  final SharedPreferences prefs;
  final _changes = StreamController<void>.broadcast();
  List<Commitment> _commitments = [];
  List<Attempt> _attempts = [];
  @override
  bool get isPreview => true;
  void _load() {
    final raw = prefs.getString('previewData');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map;
        _commitments = (j['commitments'] as List)
            .map(
              (e) => Commitment.fromJson(e['id'], Map<String, dynamic>.from(e)),
            )
            .toList();
        _attempts = (j['attempts'] as List)
            .map((e) => Attempt.fromJson(e['id'], Map<String, dynamic>.from(e)))
            .toList();
        return;
      } catch (_) {}
    }
    final now = DateTime.now();
    final s = CommitmentSchedule(
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      windowStartLocal: '00:00',
      windowEndLocal: '23:59',
      timezone: 'Asia/Kolkata',
    );
    _commitments = [
      Commitment(
        id: 'preview-walk',
        ownerUid: 'preview',
        title: 'Morning walk',
        verifierType: VerifierType.steps,
        verifierConfig: const StepsConfig(targetSteps: 1000),
        schedule: s,
        reminder: const ReminderConfig(),
        restrictions: const Restrictions(),
        status: CommitmentStatus.active,
      ),
    ];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      final w = resolveWindow(s, day);
      final date =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      _attempts.add(
        Attempt(
          id: 'preview-walk_$date',
          commitmentId: 'preview-walk',
          ownerUid: 'preview',
          date: date,
          windowStartAt: w.start,
          windowEndAt: w.end,
          state: i == 0
              ? AttemptState.pending
              : i == 4
              ? AttemptState.abandoned
              : AttemptState.completed,
          completedAt: i > 0 && i != 4
              ? w.start.add(const Duration(hours: 7))
              : null,
        ),
      );
    }
  }

  Future<void> _save() async {
    await prefs.setString(
      'previewData',
      jsonEncode({
        'commitments': _commitments
            .map((c) => {'id': c.id, ...c.toJson()})
            .toList(),
        'attempts': _attempts.map((a) => {'id': a.id, ...a.toJson()}).toList(),
      }),
    );
    _changes.add(null);
  }

  @override
  Stream<List<Commitment>> commitments() async* {
    yield _commitments;
    yield* _changes.stream.map((_) => _commitments);
  }

  @override
  Stream<List<Attempt>> attempts() async* {
    yield _attempts;
    yield* _changes.stream.map((_) => _attempts);
  }

  AppUser get _user => AppUser(
    uid: 'preview',
    displayName: 'Your next chapter',
    timezone: 'Asia/Kolkata',
    stats: UserStats(
      currentStreak: 3,
      longestStreak: 5,
      completed: _attempts
          .where((a) => a.state == AttemptState.completed)
          .length,
      abandoned: _attempts
          .where((a) => a.state == AttemptState.abandoned)
          .length,
    ),
  );
  @override
  Stream<AppUser> profile() async* {
    yield _user;
    yield* _changes.stream.map((_) => _user);
  }

  @override
  Future<void> create(Map<String, dynamic> data) async {
    if (_commitments.any((c) => c.status == CommitmentStatus.active)) {
      throw StateError(
        'Free includes one active commitment. Pause your current commitment first.',
      );
    }
    final id = 'preview-${DateTime.now().millisecondsSinceEpoch}';
    _commitments = [
      ..._commitments,
      Commitment.fromJson(id, {
        ...data,
        'ownerUid': 'preview',
        'status': 'active',
      }),
    ];
    await _save();
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {
    _commitments = _commitments
        .map(
          (c) => c.id == id
              ? Commitment.fromJson(id, {...c.toJson(), ...patch})
              : c,
        )
        .toList();
    if (patch['status'] != 'active' && patch.containsKey('status')) {
      _attempts = _attempts
          .map(
            (a) => a.commitmentId == id && a.state == AttemptState.pending
                ? Attempt.fromJson(a.id, {...a.toJson(), 'state': 'abandoned'})
                : a,
          )
          .toList();
    }
    await _save();
  }

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (name == 'syncAttempts') return {'ok': true};
    final id = '${data['commitmentId']}_${data['date']}';
    final state = name == 'endAttempt'
        ? 'abandoned'
        : name == 'reportVerifierFailure'
        ? 'unverifiable'
        : name == 'previewComplete'
        ? 'completed'
        : null;
    if (state == null) {
      throw StateError('Live verification is unavailable in preview mode.');
    }
    _attempts = _attempts
        .map(
          (a) => a.id == id && a.state == AttemptState.pending
              ? Attempt.fromJson(a.id, {...a.toJson(), 'state': state})
              : a,
        )
        .toList();
    await _save();
    return {'state': state};
  }

  @override
  Future<void> close() async {
    await _changes.close();
  }
}
