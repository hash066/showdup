import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Every moment that should be felt and heard. Names match the native cues.
enum Cue {
  /// Any button press.
  tap,

  /// Choosing between options.
  select,
  toggleOn,
  toggleOff,

  /// Moving between tabs, pages and sheets.
  page,

  /// Progress while holding to confirm. Intensity climbs with the hold.
  holdTick,
  error,

  /// The bell turning into a person.
  flip,

  /// A held app was opened.
  caught,

  /// Proof landed: showed up.
  release,

  /// A single alarm bell.
  ding,

  /// The logo sting on first launch.
  intro,

  /// Something small settling into place.
  land,
}

/// Sound and haptics for ShowdUp. Android plays ShowdUp's own synthesized
/// sounds and composed vibrations; elsewhere it falls back to system haptics.
/// Every call is fire-and-forget and never throws.
class Sensory {
  Sensory._();

  static const _channel = MethodChannel('app.showdup/sensory');

  /// Mirrors the native settings so toggles update instantly.
  static final settings = ValueNotifier<SensorySettings>(
    const SensorySettings(),
  );

  static bool _native = true;

  static Future<void> load() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('settings');
      if (raw != null) settings.value = SensorySettings.fromMap(raw);
    } on MissingPluginException {
      _native = false;
    } catch (_) {
      // Keep defaults.
    }
  }

  static Future<void> configure({
    bool? sounds,
    bool? haptics,
    String? alarmSound,
  }) async {
    settings.value = settings.value.copyWith(
      sounds: sounds,
      haptics: haptics,
      alarmSound: alarmSound,
    );
    try {
      await _channel.invokeMethod('configure', {
        'sounds': ?sounds,
        'haptics': ?haptics,
        'alarmSound': ?alarmSound,
      });
    } catch (_) {
      // Not on Android.
    }
  }

  static void play(
    Cue cue, {
    double intensity = 1,
    bool sound = true,
    bool haptic = true,
  }) {
    final current = settings.value;
    if (!_native) {
      if (haptic && current.haptics) _fallbackHaptic(cue);
      return;
    }
    unawaited(
      _channel
          .invokeMethod('cue', {
            'name': cue.name,
            'intensity': intensity.clamp(0.0, 1.0),
            'sound': sound && current.sounds,
            'haptic': haptic && current.haptics,
          })
          .catchError((Object error) {
            if (error is MissingPluginException) {
              _native = false;
              if (haptic && current.haptics) _fallbackHaptic(cue);
            }
            return null;
          }),
    );
  }

  static void _fallbackHaptic(Cue cue) {
    final Future<void> Function() haptic = switch (cue) {
      Cue.select || Cue.page || Cue.holdTick => HapticFeedback.selectionClick,
      Cue.tap || Cue.land || Cue.toggleOff => HapticFeedback.lightImpact,
      Cue.toggleOn || Cue.ding || Cue.intro => HapticFeedback.mediumImpact,
      Cue.flip ||
      Cue.caught ||
      Cue.release ||
      Cue.error => HapticFeedback.heavyImpact,
    };
    unawaited(haptic().catchError((_) {}));
  }
}

@immutable
class SensorySettings {
  const SensorySettings({
    this.sounds = true,
    this.haptics = true,
    this.alarmSound = 'showdup',
  });

  final bool sounds;
  final bool haptics;

  /// `showdup` or `system`.
  final String alarmSound;

  SensorySettings copyWith({bool? sounds, bool? haptics, String? alarmSound}) =>
      SensorySettings(
        sounds: sounds ?? this.sounds,
        haptics: haptics ?? this.haptics,
        alarmSound: alarmSound ?? this.alarmSound,
      );

  factory SensorySettings.fromMap(Map<String, dynamic> map) => SensorySettings(
    sounds: map['sounds'] != false,
    haptics: map['haptics'] != false,
    alarmSound: map['alarmSound'] == 'system' ? 'system' : 'showdup',
  );
}
