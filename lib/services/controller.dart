import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
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
    _listen();
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
  final Set<String> _starting = {};
  final Set<String> _reconciled = {};
  bool _reconciling = false;
  bool _reconcileAgain = false;
  bool _streamsFailed = false;
  bool _commitmentsLoaded = false;
  bool _disposed = false;
  String? _configuredPayload;
  Timer? _timer;
  List<Commitment> commitments = [];
  List<Attempt> attempts = [];
  AppUser? user;
  bool loading = true;
  String? error;
  bool get preview => repository.isPreview;
  static const _alarm = MethodChannel(K.alarmChannel);

  void _listen() {
    _subs.add(
      repository.commitments().listen((v) {
        commitments = v;
        loading = false;
        _commitmentsLoaded = true;
        _configure();
        notifyListeners();
      }, onError: _streamError),
    );
    _subs.add(
      repository.attempts().listen((v) {
        attempts = v;
        _reconcile();
        notifyListeners();
      }, onError: _streamError),
    );
    _subs.add(
      repository.profile().listen((v) {
        user = v;
        notifyListeners();
      }, onError: _streamError),
    );
  }

  void _error(Object e) {
    error = friendlyError(e);
    loading = false;
    notifyListeners();
  }

  /// Firestore closes a listener after it reports an error (for example a
  /// missing index or a revoked permission), so refresh() must listen again.
  void _streamError(Object e) {
    _streamsFailed = true;
    _error(e);
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_streamsFailed) {
      _streamsFailed = false;
      final old = List.of(_subs);
      _subs.clear();
      for (final s in old) {
        unawaited(s.cancel());
      }
      _listen();
    }
    if (_commitmentsLoaded && _configuredPayload == null) unawaited(_configure());
    try {
      await repository.call('syncAttempts', {});
      error = null;
    } catch (e) {
      _error(e);
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Commitment? commitment(String id) {
    for (final c in commitments) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _configure() async {
    // Never configure before the first snapshot: an empty list tells the
    // native engine to cancel every reminder.
    if (preview || _disposed || !_commitmentsLoaded) return;
    final payload = commitments
        .where((c) => c.status == CommitmentStatus.active)
        .map((c) => {'id': c.id, ...c.toJson()})
        .toList();
    final key = jsonEncode(payload);
    // Snapshots repeat for unrelated reasons; reschedule only on real change.
    if (key == _configuredPayload) return;
    _configuredPayload = key;
    try {
      await _alarm.invokeMethod('configureCommitments', {
        'commitments': payload,
      });
    } catch (e) {
      if (_configuredPayload == key) _configuredPayload = null;
      debugPrint('configureCommitments failed: $e');
      error = 'Reminders couldn’t be scheduled on this phone. Try again.';
      notifyListeners();
    }
  }

  Future<void> _reconcile() async {
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _reconcileAgain = false;
        await _reconcileOnce();
      } while (_reconcileAgain && !_disposed);
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _reconcileOnce() async {
    final now = DateTime.now();
    for (final a in attempts) {
      if (_disposed) return;
      final tracking =
          _verifiers.containsKey(a.id) || _signals.containsKey(a.id);
      if (tracking && (a.state.isTerminal || now.isAfter(a.windowEndAt))) {
        await _teardown(a.id);
      }
      if (a.state == AttemptState.completed) failures.remove(a.id);
      final recentTerminal =
          a.state.isTerminal &&
          a.windowEndAt.isAfter(now.subtract(const Duration(days: 1)));
      if (!preview &&
          recentTerminal &&
          !_reconciled.contains(a.id) &&
          await _cancelReminders(a.id)) {
        // Only remembered once native confirmed, so a failure retries.
        _reconciled.add(a.id);
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
    // A second tap while availability is checked must not arm twice.
    if (!_starting.add(a.id)) return;
    try {
      await _start(a);
    } finally {
      _starting.remove(a.id);
    }
  }

  Future<void> _start(Attempt a) async {
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
              failures.remove(a.id);
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

  /// Stops local verification. Native cleanup failures are logged, never
  /// thrown, so they cannot abort the flow that called stop().
  Future<void> stop(Attempt a) async {
    await _teardown(a.id);
    if (!preview && a.state.isTerminal && await _cancelReminders(a.id)) {
      _reconciled.add(a.id);
    }
  }

  Future<void> _teardown(String id) async {
    try {
      await _signals.remove(id)?.cancel();
    } catch (e) {
      debugPrint('Signal teardown failed for $id: $e');
    }
    try {
      await _verifiers.remove(id)?.disarm();
    } catch (e) {
      debugPrint('Verifier disarm failed for $id: $e');
    }
  }

  Future<bool> _cancelReminders(String id) async {
    try {
      await AlarmChannel.cancelReminders(id);
      return true;
    } catch (e) {
      debugPrint('cancelReminders failed for $id: $e');
      return false;
    }
  }

  /// The server decides first. If endAttempt fails the attempt is still
  /// pending, so reminders and tracking keep running and the user can retry.
  /// Cancelling reminders also silences a ringing alarm without recording a
  /// snooze.
  Future<void> end(Attempt a) async {
    await repository.call('endAttempt', {
      'commitmentId': a.commitmentId,
      'date': a.date,
      'reason': 'user_ended',
    });
    await _teardown(a.id);
    if (!preview && await _cancelReminders(a.id)) _reconciled.add(a.id);
  }

  Future<void> unable(Attempt a) async {
    await repository.call('reportVerifierFailure', {
      'commitmentId': a.commitmentId,
      'date': a.date,
      'reason': 'sensor_lost',
    });
    await _teardown(a.id);
    if (!preview && await _cancelReminders(a.id)) _reconciled.add(a.id);
  }

  Future<void> snooze(Attempt a) async {
    if (!preview) {
      await _alarm.invokeMethod('silence', {'attemptId': a.id});
    }
  }

  Future<void> shutdown() async {
    _timer?.cancel();
    Object? teardownError;
    try {
      for (final s in _subs) {
        await s.cancel();
      }
      // Includes verifiers whose attempt already left the snapshot.
      for (final id in {..._verifiers.keys, ..._signals.keys}) {
        await _teardown(id);
      }
      if (!preview) {
        try {
          await _alarm.invokeMethod('stopAll');
        } catch (e) {
          teardownError ??= e;
        }
      }
    } finally {
      await repository.close();
    }
    if (teardownError != null) {
      debugPrint('Session teardown warning: $teardownError');
    }
  }

  @override
  void dispose() {
    _disposed = true;
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

const _offline = 'You’re offline. Reconnect to sync and verify completion.';
const _tryAgain = 'Something went wrong. Please try again.';

/// Turns an error into copy a person can act on. Typed errors are mapped by
/// code; message text is only shown when it reads as a sentence, so SDK
/// tokens such as INTERNAL and stack traces never reach the screen.
String friendlyError(Object e) {
  if (e is FirebaseException) return _firebaseError(e);
  if (e is MissingPluginException) {
    return 'This feature isn’t available on this device.';
  }
  if (e is PlatformException) {
    if (e.code == 'native_error') {
      return 'Something went wrong on this phone. Please try again.';
    }
    return _sentence(e.message) ?? _tryAgain;
  }
  if (e is TimeoutException) return _offline;
  if (e is StateError) return _sentence(e.message) ?? _tryAgain;
  var message = e.toString().split('\n\n').first;
  message = message.replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
  final code = RegExp(r'^\[[^\]/]+/([^\]]+)\]').firstMatch(message)?.group(1);
  if (code == 'unavailable' || code == 'network-request-failed') {
    return _offline;
  }
  final text = message.replaceAll(RegExp(r'\[[^\]]+\]\s*'), '').trim();
  return text.isEmpty ? _tryAgain : text;
}

String _firebaseError(FirebaseException e) {
  final fromServer = e.plugin == 'firebase_functions';
  final message = _sentence(e.message);
  switch (e.code) {
    case 'unavailable':
    case 'network-request-failed':
      return _offline;
    case 'deadline-exceeded':
      return 'The server took too long to respond. Check your connection and try again.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is incorrect.';
    case 'email-already-in-use':
      return 'This email already has an account. Sign in instead.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes and try again.';
    case 'unauthenticated':
      // The SDK's bare "Unauthenticated" means the sign-in or App Check token
      // was rejected; the server's own reasons are full sentences.
      return (fromServer ? message : null) ??
          'We couldn’t confirm this session. Sign out and sign in again, and make sure the app is installed from Google Play.';
    case 'permission-denied':
      return 'Access was denied. Sign out and sign in again.';
    case 'resource-exhausted':
      return (fromServer ? message : null) ??
          'Too many requests right now. Wait a moment and try again.';
    case 'not-found':
      if (fromServer && message != null && message != 'Not found.') {
        return message;
      }
      return 'This commitment is no longer available.';
    case 'failed-precondition':
    case 'invalid-argument':
    case 'already-exists':
    case 'out-of-range':
      // Only callable functions word these for people; Firestore's
      // failed-precondition, for example, describes a missing index.
      return (fromServer || e.plugin == 'firebase_auth' ? message : null) ??
          _tryAgain;
    case 'internal':
    case 'unknown':
    case 'data-loss':
      return 'Something went wrong on our side. Please try again in a moment.';
    default:
      return (e.plugin == 'firebase_auth' || fromServer ? message : null) ??
          _tryAgain;
  }
}

String? _sentence(String? message) {
  final text = message?.split('\n\n').first.trim() ?? '';
  if (text.isEmpty || !text.contains(' ') || text == text.toUpperCase()) {
    return null;
  }
  return text;
}
