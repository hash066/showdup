import 'package:flutter/services.dart';
import '../core/constants.dart';

class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.isMock,
    required this.epochMs,
  });

  final double lat;
  final double lng;
  final double accuracyM;

  /// If true the fix is discarded, both client and server side.
  final bool isMock;
  final int epochMs;

  factory LocationFix.fromMap(Map m) => LocationFix(
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    accuracyM: (m['accuracyM'] as num).toDouble(),
    isMock: m['isMock'] == true,
    epochMs: (m['epochMs'] as num).toInt(),
  );
}

class LocationEvent {
  const LocationEvent(
    this.type,
    this.attemptId,
    this.distanceM,
    this.dwellMs,
    this.fix,
  );
  final String type; // fix | dwell_progress | dwell_satisfied | unavailable
  final String attemptId;
  final double distanceM;
  final int dwellMs;
  final LocationFix? fix;

  factory LocationEvent.fromMap(Map m) => LocationEvent(
    m['type'] as String,
    m['attemptId'] as String,
    (m['distanceM'] as num?)?.toDouble() ?? -1,
    (m['dwellMs'] as num?)?.toInt() ?? 0,
    m['fix'] == null ? null : LocationFix.fromMap(m['fix'] as Map),
  );
}

/// Foreground-service location only. See LocationVerifier for why we do
/// not use the Geofencing API.
class LocationChannel {
  static const _m = MethodChannel(K.locationChannel);
  static const _e = EventChannel(K.locationEvents);

  /// Starts the location foreground service. MUST be called while the app
  /// is visible, for example straight after the user taps a reminder.
  static Future<bool> startWatch({
    required String attemptId,
    required double lat,
    required double lng,
    required int radiusM,
    required int dwellMs,
    required int untilEpochMs,
  }) async =>
      await _m.invokeMethod<bool>('startWatch', {
        'attemptId': attemptId,
        'lat': lat,
        'lng': lng,
        'radiusM': radiusM,
        'dwellMs': dwellMs,
        'untilEpochMs': untilEpochMs,
      }) ??
      false;

  static Future<bool> stopWatch(String attemptId) async =>
      await _m.invokeMethod<bool>('stopWatch', {'attemptId': attemptId}) ??
      false;

  static Future<bool> isWatching() async =>
      await _m.invokeMethod<bool>('isWatching') ?? false;

  static final Stream<LocationEvent> _stream = _e.receiveBroadcastStream().map(
    (e) => LocationEvent.fromMap(e as Map),
  );
  static Stream<LocationEvent> events() => _stream;
}
