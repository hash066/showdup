import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../models/enums.dart';

class AlarmPermissionStatus {
  const AlarmPermissionStatus({
    required this.exactAlarm,
    required this.notifications,
    required this.batteryOptimised,
    required this.fullScreenIntent,
    required this.activityRecognition,
    required this.location,
  });

  final bool exactAlarm;
  final bool notifications;
  final bool batteryOptimised; // true means the OS may kill us
  final bool fullScreenIntent;
  final bool activityRecognition;
  final bool location;

  bool get allGranted =>
      exactAlarm && notifications && !batteryOptimised && fullScreenIntent;

  factory AlarmPermissionStatus.fromMap(Map m) => AlarmPermissionStatus(
    exactAlarm: m['exactAlarm'] == true,
    notifications: m['notifications'] == true,
    batteryOptimised: m['batteryOptimised'] == true,
    fullScreenIntent: m['fullScreenIntent'] == true,
    activityRecognition: m['activityRecognition'] == true,
    location: m['location'] == true,
  );
}

class AlarmEvent {
  const AlarmEvent(this.type, this.attemptId, this.index, {this.source});
  final String type; // fired | snoozed | expired
  final String attemptId;
  final int index;
  final String? source; // manual | automatic

  factory AlarmEvent.fromMap(Map m) => AlarmEvent(
    m['type'] as String,
    m['attemptId'] as String,
    (m['index'] as num?)?.toInt() ?? 0,
    source: m['source'] as String?,
  );
}

/// FROZEN CONTRACT. Agent 1 implements the Kotlin side against exactly this.
class AlarmChannel {
  static const _m = MethodChannel(K.alarmChannel);
  static const _e = EventChannel(K.alarmEvents);

  static Future<bool> scheduleReminders({
    required String attemptId,
    required int startEpochMs,
    required int endEpochMs,
    required int intervalMinutes,
    required VolumeMode volumeMode,
    required int maxReminders,
  }) async =>
      await _m.invokeMethod<bool>('scheduleReminders', {
        'attemptId': attemptId,
        'startEpochMs': startEpochMs,
        'endEpochMs': endEpochMs,
        'intervalMinutes': intervalMinutes,
        'volumeMode': volumeMode.wire,
        'maxReminders': maxReminders,
      }) ??
      false;

  static Future<bool> cancelReminders(String attemptId) async =>
      await _m.invokeMethod<bool>('cancelReminders', {
        'attemptId': attemptId,
      }) ??
      false;

  static Future<AlarmPermissionStatus> getPermissionStatus() async {
    final m = await _m.invokeMethod<Map>('getPermissionStatus');
    return AlarmPermissionStatus.fromMap(m ?? const {});
  }

  static Future<bool> requestPermission(String which) async =>
      await _m.invokeMethod<bool>('requestPermission', {'which': which}) ??
      false;

  /// Returns and consumes the attempt opened from an alarm notification.
  /// Native code clears it after this call so a process resume cannot reopen
  /// the same attempt repeatedly.
  static Future<String?> getLaunchAttempt() =>
      _m.invokeMethod<String>('getLaunchAttempt');

  static Stream<AlarmEvent> events() =>
      _e.receiveBroadcastStream().map((e) => AlarmEvent.fromMap(e as Map));

  /// Hands a regular alarm to the user's chosen Clock app. Android exposes no
  /// reliable cross-vendor API for reading its later state back into ShowdUp.
  static Future<bool> createNativeAlarm({
    required int hour,
    required int minute,
    required String label,
    List<int> days = const [],
  }) async =>
      await _m.invokeMethod<bool>('createNativeAlarm', {
        'hour': hour,
        'minute': minute,
        'label': label,
        'days': days,
      }) ??
      false;

  static Future<bool> showNativeAlarms() async =>
      await _m.invokeMethod<bool>('showNativeAlarms') ?? false;

  /// Rings one real reminder in [seconds], through the same notification
  /// channel, full-screen intent and alarm sound as a proof alarm.
  static Future<bool> testAlarm({int seconds = 10}) async =>
      await _m.invokeMethod<bool>('testAlarm', {'seconds': seconds}) ?? false;
}
