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
  });

  final bool accessibilityEnabled;
  final bool active;

  factory BlockerStatus.fromMap(Map<dynamic, dynamic> value) => BlockerStatus(
    accessibilityEnabled: value['accessibilityEnabled'] == true,
    active: value['active'] == true,
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

  static Future<void> sync(List<BlockerSession> sessions) =>
      _channel.invokeMethod<void>('sync', {
        'sessions': sessions.map((session) => session.toMap()).toList(),
      });

  static Future<void> setEntitlement({
    required bool enabled,
    required int? expiresAtEpochMs,
  }) => _channel.invokeMethod<void>('setEntitlement', {
    'enabled': enabled,
    'expiresAtEpochMs': expiresAtEpochMs,
  });

  static Future<void> stop() => _channel.invokeMethod<void>('stop');
}
