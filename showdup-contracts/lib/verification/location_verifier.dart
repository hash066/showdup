import 'dart:async';
import '../models/attempt.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import 'verifier.dart';

/// v1 verifier. FOREGROUND ONLY.
///
/// Deliberately does NOT use the Geofencing API, because geofences that
/// fire while the app is not running require ACCESS_BACKGROUND_LOCATION,
/// which needs a Play declaration plus a demo video and adds review time
/// we do not have.
///
/// Instead: when the user taps a reminder, the app comes to the
/// foreground and starts a foreground service with
/// foregroundServiceType="location". Inside that service we request
/// periodic FusedLocationProvider updates and compute distance and dwell
/// ourselves. Permissions needed: ACCESS_FINE_LOCATION,
/// ACCESS_COARSE_LOCATION, FOREGROUND_SERVICE_LOCATION. No background
/// location permission anywhere.
///
/// Consequence to surface honestly in the UI: if the user never opens the
/// app or taps a reminder, nothing verifies and the attempt expires.
///
/// AGENT 4: implement.
///  - require ENTER plus continuous dwell of config.dwellMs, never a
///    single fix
///  - discard any fix where isMock is true
///  - discard fixes with accuracy worse than radiusM
///  - use balanced power priority, roughly 60s interval, to survive a
///    two hour window without destroying the battery
///  - stop the service the instant the server confirms completion
class LocationVerifier implements Verifier {
  @override
  VerifierType get type => VerifierType.location;

  @override
  Future<VerifierAvailability> checkAvailability(VerifierConfig config) {
    throw UnimplementedError();
  }

  @override
  Future<void> arm(Attempt attempt, VerifierConfig config) {
    throw UnimplementedError();
  }

  @override
  Stream<VerificationSignal> signals() {
    throw UnimplementedError();
  }

  @override
  Future<void> disarm() {
    throw UnimplementedError();
  }
}
