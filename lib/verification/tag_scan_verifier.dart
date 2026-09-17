import 'dart:async';

import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/scanner_channel.dart';
import 'verifier.dart';

/// Proof by scanning the tag you placed where the habit happens.
class TagScanVerifier implements Verifier {
  TagScanVerifier({Future<String?> Function()? scan})
    : _scan = scan ?? ScannerChannel.scan;

  final Future<String?> Function() _scan;
  final _signals = StreamController<VerificationSignal>.broadcast();

  @override
  VerifierType get type => VerifierType.tagScan;

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) async {
    final problem = config is TagScanConfig
        ? config.validate()
        : 'Invalid tag setup.';
    return problem == null
        ? VerifierAvailability.ok
        : VerifierAvailability(available: false, reason: problem);
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) async {
    final tag = config as TagScanConfig;
    final hash = await _scan();
    if (hash == null) {
      throw StateError('Scan your tag to prove it.');
    }
    if (hash != tag.codeHash) {
      throw StateError('That’s a different code. Scan the tag you set up.');
    }
    _signals.add(
      VerificationSignal.satisfied(
        evidenceEnvelope(
          verifier: type,
          source: 'google_code_scanner',
          integrityFlags: const ['camera_scan', 'matching_code_hash'],
          details: {if (tag.label != null) 'label': tag.label},
        ),
      ),
    );
  }

  @override
  Stream<VerificationSignal> signals() => _signals.stream;

  @override
  Future<void> disarm() async {}
}
