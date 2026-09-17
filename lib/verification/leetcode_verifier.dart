import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import 'verifier.dart';

/// Reads a public LeetCode profile. Beta: LeetCode's public API is
/// unofficial, so an outage marks the day "couldn't tell", never missed.
class LeetCodeVerifier implements Verifier {
  final _signals = StreamController<VerificationSignal>.broadcast();
  Timer? _poller;
  HttpClient? _client;
  bool _satisfied = false;
  bool _armed = false;
  int _failures = 0;

  static const _baseInterval = Duration(seconds: 45);
  static const _maxInterval = Duration(minutes: 5);

  @override
  VerifierType get type => VerifierType.leetcode;

  /// A short code the person pastes into their profile's About field to show
  /// the username is theirs. Unambiguous characters only.
  static String newOwnershipCode([Random? random]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = random ?? Random.secure();
    return 'showdup-${List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join()}';
  }

  /// True when the public profile's About text contains [code].
  static Future<bool> profileContains(String username, String code) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final data = await _query(
        client,
        r'''query profile($username: String!) {
          matchedUser(username: $username) { profile { aboutMe } }
        }''',
        {'username': username.trim()},
      );
      final user = data['matchedUser'] as Map<String, dynamic>?;
      if (user == null) {
        throw StateError('No public LeetCode profile with that username.');
      }
      final about = (user['profile'] as Map?)?['aboutMe']?.toString() ?? '';
      return about.toLowerCase().contains(code.toLowerCase());
    } on SocketException {
      throw StateError('Couldn’t reach LeetCode. Check your connection.');
    } on TimeoutException {
      throw StateError('LeetCode took too long. Try again.');
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _query(
    HttpClient client,
    String query,
    Map<String, dynamic> variables,
  ) async {
    final request = await client.postUrl(
      Uri.https('leetcode.com', '/graphql/'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.userAgentHeader, 'ShowdUp/1.0 public-profile-check')
      ..set(HttpHeaders.refererHeader, 'https://leetcode.com/');
    request.write(jsonEncode({'query': query, 'variables': variables}));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('LeetCode returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['data'] as Map<String, dynamic>? ?? const {};
  }

  /// Waits longer after each failure, up to five minutes.
  static Duration backoff(int failures) {
    if (failures <= 0) return _baseInterval;
    final seconds = _baseInterval.inSeconds * pow(2, min(failures, 6));
    return Duration(seconds: min(seconds.toInt(), _maxInterval.inSeconds));
  }

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    if (config is! LeetCodeConfig || config.validate() != null) {
      return VerifierAvailability(
        available: false,
        reason: config.validate() ?? 'Invalid LeetCode configuration.',
      );
    }
    return VerifierAvailability.ok;
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final leetcode = config as LeetCodeConfig;
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    _satisfied = false;
    _armed = true;
    _failures = 0;

    Future<void> poll() async {
      if (_satisfied || !_armed) return;
      try {
        final data = await _query(
          _client!,
          r'''query recentAcSubmissions($username: String!, $limit: Int!) {
              recentAcSubmissionList(username: $username, limit: $limit) {
                id title titleSlug timestamp
              }
            }''',
          {'username': leetcode.username, 'limit': 40},
        );
        final raw = data['recentAcSubmissionList'] as List?;
        if (raw == null) {
          throw const FormatException('Public profile was not found.');
        }
        final start = attempt.windowStartAt.millisecondsSinceEpoch ~/ 1000;
        final end = attempt.windowEndAt.millisecondsSinceEpoch ~/ 1000;
        final accepted = <String, Map<String, dynamic>>{};
        for (final value in raw) {
          final item = Map<String, dynamic>.from(value as Map);
          final timestamp = int.tryParse(item['timestamp']?.toString() ?? '');
          final slug = item['titleSlug']?.toString();
          if (timestamp != null &&
              slug != null &&
              timestamp >= start &&
              timestamp <= end) {
            accepted.putIfAbsent(slug, () => item);
          }
        }
        _failures = 0;
        final count = accepted.length;
        if (count >= leetcode.targetAccepted) {
          _satisfied = true;
          _signals.add(
            VerificationSignal.satisfied({
              'schemaVersion': 1,
              'verifier': type.wire,
              'source': 'leetcode_public_profile',
              'capturedAt': DateTime.now().millisecondsSinceEpoch,
              'integrityFlags': [
                'public_profile',
                'unique_problem_slugs',
                if (leetcode.ownerVerifiedAtMs != null)
                  'profile_ownership_code',
              ],
              'username': leetcode.username,
              'acceptedCount': count,
              'problemSlugs': accepted.keys.toList()..sort(),
            }),
          );
        } else {
          _signals.add(
            VerificationSignal.progressAt(
              (count / leetcode.targetAccepted).clamp(0.0, 1.0),
            ),
          );
        }
      } catch (_) {
        _failures++;
        if (_failures >= 3) {
          _signals.add(
            const VerificationSignal.cannotVerify(
              'LeetCode’s public profile service is unavailable. This day won’t count as a miss.',
            ),
          );
        }
      }
      if (!_satisfied && _armed) {
        _poller = Timer(backoff(_failures), poll);
      }
    }

    await poll();
  }

  @override
  Stream<VerificationSignal> signals() => _signals.stream;

  @override
  Future<void> disarm() async {
    _armed = false;
    _poller?.cancel();
    _poller = null;
    _client?.close(force: true);
    _client = null;
  }
}
