import 'package:flutter/services.dart';
import '../core/constants.dart';

class StepReading {
  const StepReading({
    required this.cumulativeSteps,
    required this.sensorBootTime,
    required this.available,
  });

  final int cumulativeSteps;

  /// Changes across a reboot. Used to detect the counter reset.
  final int sensorBootTime;
  final bool available;

  factory StepReading.fromMap(Map m) => StepReading(
    cumulativeSteps: (m['cumulativeSteps'] as num?)?.toInt() ?? 0,
    sensorBootTime: (m['sensorBootTime'] as num?)?.toInt() ?? 0,
    available: m['available'] == true,
  );
}

class StepEvent {
  const StepEvent(
    this.type,
    this.attemptId,
    this.stepsSinceBaseline,
    this.elapsedMs,
  );
  final String type; // progress | target_reached | sensor_lost
  final String attemptId;
  final int stepsSinceBaseline;
  final int elapsedMs;

  factory StepEvent.fromMap(Map m) => StepEvent(
    m['type'] as String,
    m['attemptId'] as String,
    (m['stepsSinceBaseline'] as num?)?.toInt() ?? 0,
    (m['elapsedMs'] as num?)?.toInt() ?? 0,
  );
}

class StepsChannel {
  static const _m = MethodChannel(K.stepsChannel);
  static const _e = EventChannel(K.stepsEvents);

  static Future<StepReading> getStepCount() async => StepReading.fromMap(
    await _m.invokeMethod<Map>('getStepCount') ?? const {},
  );

  static Future<bool> startTracking({
    required String attemptId,
    required int baselineSteps,
    required int targetSteps,
  }) async =>
      await _m.invokeMethod<bool>('startTracking', {
        'attemptId': attemptId,
        'baselineSteps': baselineSteps,
        'targetSteps': targetSteps,
      }) ??
      false;

  static Future<bool> stopTracking(String attemptId) async =>
      await _m.invokeMethod<bool>('stopTracking', {'attemptId': attemptId}) ??
      false;

  static final Stream<StepEvent> _stream = _e.receiveBroadcastStream().map((e) => StepEvent.fromMap(e as Map));
  static Stream<StepEvent> events() => _stream;
}
