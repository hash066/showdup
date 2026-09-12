import '../models/enums.dart';
import 'location_verifier.dart';
import 'steps_verifier.dart';
import 'walk_verifier.dart';
import 'verifier.dart';

/// The only place that knows which verifiers exist. Adding one in v1.1
/// should mean adding one line here and nothing else.
class VerifierRegistry {
  VerifierRegistry({Map<VerifierType, Verifier Function()>? overrides})
    : _factories =
          overrides ??
          {
            VerifierType.steps: StepsVerifier.new,
            VerifierType.location: LocationVerifier.new,
            VerifierType.walk: WalkVerifier.new,
          };

  final Map<VerifierType, Verifier Function()> _factories;

  Verifier create(VerifierType type) {
    final f = _factories[type];
    if (f == null) throw StateError('No verifier registered for $type');
    return f();
  }

  Iterable<VerifierType> get supported => _factories.keys;
}
