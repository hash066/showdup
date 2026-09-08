import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/commitment.dart';
import '../models/attempt.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../platform/alarm_channel.dart';
import '../verification/verifier.dart';
import '../verification/verifier_registry.dart';
import 'repository.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository) {
    _subs.add(
      repository.commitments().listen((v) {
        commitments = v;
        loading = false;
        _configure();
        notifyListeners();
      }, onError: _error),
    );
    _subs.add(
      repository.attempts().listen((v) {
        attempts = v;
        _reconcile();
        notifyListeners();
      }, onError: _error),
    );
    _subs.add(
      repository.profile().listen((v) {
        user = v;
        notifyListeners();
      }, onError: _error),
    );
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      _reconcile();
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
      await repository.call('syncAttempts', {});
      error = null;
    } catch (e) {
      _error(e);
    }
    notifyListeners();
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
              .map((c) => {'id': c.id, ...c.toJson()})
              .toList(),
        },
      );
    } catch (e) {
      _error(e);
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

  Future<void> end(Attempt a) async {
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
