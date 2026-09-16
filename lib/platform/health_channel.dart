import 'package:flutter/services.dart';

import '../core/constants.dart';

class HealthAvailability {
  const HealthAvailability({
    required this.available,
    required this.permissionsGranted,
    this.reason,
  });

  final bool available;
  final bool permissionsGranted;
  final String? reason;

  factory HealthAvailability.fromMap(Map value) => HealthAvailability(
    available: value['available'] == true,
    permissionsGranted: value['permissionsGranted'] == true,
    reason: value['reason'] as String?,
  );
}

class HealthChannel {
  static const _channel = MethodChannel(K.healthChannel);

  static Future<HealthAvailability> availability() async =>
      HealthAvailability.fromMap(
        await _channel.invokeMethod<Map>('availability') ?? const {},
      );

  static Future<bool> requestPermissions() async =>
      await _channel.invokeMethod<bool>('requestPermissions') ?? false;

  static Future<Map<String, dynamic>> checkWorkout({
    required int startEpochMs,
    required int endEpochMs,
    required int targetDurationMs,
    required String activityType,
  }) async => Map<String, dynamic>.from(
    await _channel.invokeMethod<Map>('checkWorkout', {
          'startEpochMs': startEpochMs,
          'endEpochMs': endEpochMs,
          'targetDurationMs': targetDurationMs,
          'activityType': activityType,
        }) ??
        const {},
  );
}
