import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/attempt.dart';
import '../models/battle.dart';
import '../models/pet.dart';

class SocialService {
  SocialService._();
  static final instance = SocialService._();
  String? pendingInviteCode;
  Battle? latestBattle;
  List<BattleMemberScore> latestScores = const [];
  StreamSubscription<Battle?>? _battleSubscription;
  StreamSubscription<List<BattleMemberScore>>? _scoreSubscription;
  final _battleUpdates = StreamController<Battle?>.broadcast();
  final _scoreUpdates = StreamController<List<BattleMemberScore>>.broadcast();
  int _watchGeneration = 0;

  bool get available => Firebase.apps.isNotEmpty;
  User? get user => available ? FirebaseAuth.instance.currentUser : null;
  bool get googleLinked =>
      user?.providerData.any(
        (provider) => provider.providerId == 'google.com',
      ) ==
      true;

  Future<User?> ensureAnonymous() async {
    if (!available) return null;
    return FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user;
  }

  Future<void> startWatching() async {
    if (!available || _battleSubscription != null) return;
    _battleSubscription = activeBattle().listen((battle) async {
      final generation = ++_watchGeneration;
      latestBattle = battle;
      latestScores = const [];
      _battleUpdates.add(battle);
      _scoreUpdates.add(const []);
      await _scoreSubscription?.cancel();
      if (generation != _watchGeneration) return;
      _scoreSubscription = null;
      if (battle != null) {
        _scoreSubscription = scores(battle.id).listen((value) {
          if (generation != _watchGeneration) return;
          latestScores = value;
          _scoreUpdates.add(value);
        }, onError: _scoreUpdates.addError);
      }
    }, onError: _battleUpdates.addError);
  }

  Stream<Battle?> battleStates() async* {
    yield latestBattle;
    yield* _battleUpdates.stream;
  }

  Stream<List<BattleMemberScore>> scoreStates() async* {
    yield latestScores;
    yield* _scoreUpdates.stream;
  }

  Future<User> linkGoogle() async {
    final current = await ensureAnonymous();
    if (current == null) {
      throw StateError('Social features are not configured in this build.');
    }
    if (googleLinked) return current;
    final provider = GoogleAuthProvider()..addScope('profile');
    try {
      final linked = (await current.linkWithProvider(provider)).user!;
      await linked.getIdToken(true);
      return linked;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'credential-already-in-use' ||
          error.code == 'provider-already-linked') {
        throw StateError(
          'That Google account already has ShowdUp data. Sign-in merge needs confirmation from the account screen.',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    await ensureAnonymous();
    final value =
        (await FirebaseFunctions.instance.httpsCallable(name).call(data)).data;
    return Map<String, dynamic>.from(value as Map);
  }

  Stream<Battle?> activeBattle() async* {
    final current = await ensureAnonymous();
    if (current == null) {
      yield null;
      return;
    }
    yield* FirebaseFirestore.instance
        .collection('battles')
        .where('memberUids', arrayContains: current.uid)
        .limit(1)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.isEmpty
              ? null
              : Battle.fromJson(
                  snapshot.docs.first.id,
                  snapshot.docs.first.data(),
                ),
        );
  }

  Stream<List<BattleMemberScore>> scores(String battleId) => FirebaseFirestore
      .instance
      .collection('battles/$battleId/scores')
      .orderBy('score', descending: true)
      .limit(10)
      .snapshots()
      .map(
        (snapshot) => [
          for (var i = 0; i < snapshot.docs.length; i++)
            BattleMemberScore.fromJson(snapshot.docs[i].id, {
              ...snapshot.docs[i].data(),
              'rank': i + 1,
            }),
        ],
      );

  Future<String> createBattle({
    required String timezone,
    required MascotId mascot,
  }) async {
    await linkGoogle();
    return (await _call('createBattle', {
          'name': 'Weekly battle',
          'timezone': timezone,
          'mascot': mascot.wire,
        }))['battleId']
        as String;
  }

  Future<BattleInvite> createInvite(String battleId) async {
    await linkGoogle();
    final result = await _call('createBattleInvite', {'battleId': battleId});
    return BattleInvite(
      code: result['code'] as String,
      url: result['url'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (result['expiresAt'] as num).toInt(),
      ),
    );
  }

  Future<void> join(String code) async {
    await linkGoogle();
    await _call('joinBattle', {'code': code.trim().toUpperCase()});
  }

  Future<void> leave(String battleId) =>
      _call('leaveBattle', {'battleId': battleId});

  Future<void> deleteAccount() async {
    if (!available || user == null) return;
    if (googleLinked) {
      final provider = GoogleAuthProvider()..addScope('profile');
      await user!.reauthenticateWithProvider(provider);
      await user!.getIdToken(true);
    }
    await _call('deleteSocialAccount');
    latestBattle = null;
    latestScores = const [];
    _watchGeneration++;
    await _battleSubscription?.cancel();
    await _scoreSubscription?.cancel();
    _battleSubscription = null;
    _scoreSubscription = null;
    _battleUpdates.add(null);
    _scoreUpdates.add(const []);
  }

  Future<bool> syncOutcome(Attempt attempt, PetSnapshot pet) async {
    if (!available || !googleLinked || !attempt.state.isTerminal) return false;
    await _call('submitBattleOutcome', {
      'eventId': attempt.id,
      'outcome': attempt.state.wire,
      'snoozes': attempt.snoozes,
      'resolvedAt':
          (attempt.completedAt ?? attempt.windowEndAt).millisecondsSinceEpoch,
      'petMood': pet.mood.wire,
      'burstCount': pet.burstCount,
      'mascot': pet.mascot.wire,
    });
    return true;
  }
}
