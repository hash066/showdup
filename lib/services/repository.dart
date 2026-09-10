import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/commitment.dart';
import '../models/attempt.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../core/scheduling.dart';

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

/// One unreadable document must not blank, or error, the whole list.
List<T> _parseDocs<T>(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  T Function(String id, Map<String, dynamic> data) parse,
) {
  final out = <T>[];
  for (final d in docs) {
    try {
      out.add(parse(d.id, d.data()));
    } catch (e) {
      debugPrint('Skipping unreadable ${d.reference.path}: $e');
    }
  }
  return out;
}

class FirebaseRepository implements Repository {
  FirebaseRepository(this.uid);
  final String uid;
  final _db = FirebaseFirestore.instance;
  @override
  bool get isPreview => false;
  @override
  Stream<List<Commitment>> commitments() => _db
      .collection('commitments')
      .where('ownerUid', isEqualTo: uid)
      .snapshots()
      .map((s) => _parseDocs(s.docs, Commitment.fromJson));
  @override
  Stream<List<Attempt>> attempts() => _db
      .collection('attempts')
      .where('ownerUid', isEqualTo: uid)
      .orderBy('date', descending: true)
      .limit(1000)
      .snapshots()
      .map((s) => _parseDocs(s.docs, Attempt.fromJson));
  @override
  Stream<AppUser> profile() => _db
      .doc('users/$uid')
      .snapshots()
      .map((s) => AppUser.fromJson(uid, s.data() ?? {}));
  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    (await FirebaseFunctions.instance.httpsCallable(name).call(data)).data
        as Map,
  );
  @override
  Future<void> create(Map<String, dynamic> data) async {
    await call('createCommitment', data);
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {
    await call('updateCommitment', {'commitmentId': id, 'patch': patch});
  }

  @override
  Future<void> close() async {
    await FirebaseAuth.instance.signOut();
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
      // A UTC date carrier avoids device DST gaps at local midnight.
      final day = DateTime.utc(now.year, now.month, now.day - i);
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
