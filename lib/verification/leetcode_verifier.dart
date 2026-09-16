import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import 'verifier.dart';

class LeetCodeVerifier implements Verifier {
  final _signals = StreamController<VerificationSignal>.broadcast();
  Timer? _poller;
  HttpClient? _client;
  bool _satisfied = false;
  int _failures = 0;

  @override
  VerifierType get type => VerifierType.leetcode;

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
    _failures = 0;

    Future<void> poll() async {
      if (_satisfied) return;
      try {
        final request = await _client!.postUrl(
          Uri.https('leetcode.com', '/graphql/'),
        );
        request.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.userAgentHeader, 'ShowdUp/1.0 public-profile-check')
          ..set(HttpHeaders.refererHeader, 'https://leetcode.com/');
        request.write(
          jsonEncode({
            'query':
                r'''query recentAcSubmissions($username: String!, $limit: Int!) {
              recentAcSubmissionList(username: $username, limit: $limit) {
                id title titleSlug timestamp
              }
            }''',
            'variables': {'username': leetcode.username, 'limit': 40},
          }),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode != 200) {
          throw HttpException('LeetCode returned ${response.statusCode}.');
        }
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>?;
        final raw = data?['recentAcSubmissionList'] as List?;
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
              'integrityFlags': const [
                'public_profile',
                'unique_problem_slugs',
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
              'LeetCode’s public profile service is unavailable. This attempt will not count as a miss.',
            ),
          );
        }
      }
    }

    await poll();
    _poller = Timer.periodic(const Duration(seconds: 45), (_) => poll());
  }

  @override
  Stream<VerificationSignal> signals() => _signals.stream;

  @override
  Future<void> disarm() async {
    _poller?.cancel();
    _poller = null;
    _client?.close(force: true);
    _client = null;
  }
}
