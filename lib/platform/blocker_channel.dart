import 'package:flutter/services.dart';

import '../core/constants.dart';

class BlockableApp {
  const BlockableApp({required this.packageName, required this.label});

  final String packageName;
  final String label;

  factory BlockableApp.fromMap(Map<dynamic, dynamic> value) => BlockableApp(
    packageName: value['packageName'] as String,
    label: value['label'] as String,
  );
}

class BlockerStatus {
  const BlockerStatus({
    required this.accessibilityEnabled,
    required this.active,
    this.quickCatch = true,
  });

  final bool accessibilityEnabled;
  final bool active;

  /// After the first catch of the day, later reaches get the small flash
  /// instead of the full Caught screen.
  final bool quickCatch;

  factory BlockerStatus.fromMap(Map<dynamic, dynamic> value) => BlockerStatus(
    accessibilityEnabled: value['accessibilityEnabled'] == true,
    active: value['active'] == true,
    quickCatch: value['quickCatch'] != false,
  );
}

class BlockerSession {
  const BlockerSession({
    required this.attemptId,
    required this.commitmentId,
    required this.packages,
    required this.activeFromEpochMs,
    required this.activeUntilEpochMs,
  });

  final String attemptId;
  final String commitmentId;
  final List<String> packages;
  final int activeFromEpochMs;
  final int activeUntilEpochMs;

  Map<String, dynamic> toMap() => {
    'attemptId': attemptId,
    'commitmentId': commitmentId,
    'packages': packages,
    'activeFromEpochMs': activeFromEpochMs,
    'activeUntilEpochMs': activeUntilEpochMs,
  };
}

class BlockerChannel {
  BlockerChannel._();

  static const _channel = MethodChannel(K.blockerChannel);

  static Future<List<BlockableApp>> listApps() async {
    final values = await _channel.invokeMethod<List<dynamic>>('listApps');
    return (values ?? const [])
        .map((value) => BlockableApp.fromMap(value as Map))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  static Future<BlockerStatus> status() async => BlockerStatus.fromMap(
    await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus') ?? const {},
  );

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  /// Turns the small Caught flash on or off. Off means every reach shows the
  /// full Caught screen.
  static Future<void> setQuickCatch(bool enabled) =>
      _channel.invokeMethod<void>('setQuickCatch', {'enabled': enabled});

  static Future<void> sync(List<BlockerSession> sessions) =>
      _channel.invokeMethod<void>('sync', {
        'sessions': sessions.map((session) => session.toMap()).toList(),
      });

  /// [freeCatch] lets a free person hold one app. Native code clamps free
  /// sessions to a single app, so edited preferences cannot unlock more.
  static Future<void> setEntitlement({
    required bool enabled,
    required int? expiresAtEpochMs,
    bool freeCatch = false,
  }) => _channel.invokeMethod<void>('setEntitlement', {
    'enabled': enabled,
    'expiresAtEpochMs': expiresAtEpochMs,
    'freeCatch': freeCatch,
  });

  /// How many times each attempt's held app was opened, keyed by attempt id.
  static Future<Map<String, int>> reaches() async {
    final raw = await _channel.invokeMethod<Map>('reaches') ?? const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  static Future<Map<String, String>> appLabels(List<String> packages) async {
    final raw =
        await _channel.invokeMethod<Map>('appLabels', {'packages': packages}) ??
        const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static Future<bool> openApp(String packageName) async =>
      await _channel.invokeMethod<bool>('openApp', {
        'packageName': packageName,
      }) ??
      false;

  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  static Future<bool> startFocus({
    required String attemptId,
    required List<String> packages,
    required int startEpochMs,
    required int endEpochMs,
    required int targetDurationMs,
    int graceSeconds = 10,
  }) async =>
      await _channel.invokeMethod<bool>('startFocus', {
        'attemptId': attemptId,
        'packages': packages,
        'startEpochMs': startEpochMs,
        'endEpochMs': endEpochMs,
        'targetDurationMs': targetDurationMs,
        'graceSeconds': graceSeconds,
      }) ??
      false;

  static Future<Map<String, dynamic>> focusStatus(String attemptId) async =>
      Map<String, dynamic>.from(
        await _channel.invokeMethod<Map>('focusStatus', {
              'attemptId': attemptId,
            }) ??
            const {},
      );

  static Future<void> stopFocus(String attemptId) =>
      _channel.invokeMethod<void>('stopFocus', {'attemptId': attemptId});
}
