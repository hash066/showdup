import 'package:flutter/services.dart';
import '../models/pet.dart';

class OverlayStatus {
  const OverlayStatus({
    required this.permissionGranted,
    required this.enabled,
    required this.running,
  });
  final bool permissionGranted;
  final bool enabled;
  final bool running;

  factory OverlayStatus.fromMap(Map? map) => OverlayStatus(
    permissionGranted: map?['permissionGranted'] == true,
    enabled: map?['enabled'] == true,
    running: map?['running'] == true,
  );
}

class OverlayChannel {
  const OverlayChannel._();
  static const _channel = MethodChannel('app.showdup/overlay');

  static Future<OverlayStatus> status() async =>
      OverlayStatus.fromMap(await _channel.invokeMethod<Map>('status'));

  static Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  static Future<bool> enable() async =>
      await _channel.invokeMethod<bool>('enable') ?? false;

  static Future<void> disable() => _channel.invokeMethod<void>('disable');

  /// [companionImage] is a PNG path the bubble draws instead of an emoji.
  static Future<void> sync(PetSnapshot snapshot, {String? companionImage}) =>
      _channel.invokeMethod<void>('syncSnapshot', {
        ...snapshot.toJson(),
        'companionImage': ?companionImage,
      });
}
