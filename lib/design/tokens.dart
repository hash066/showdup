import 'package:flutter/animation.dart';

/// ShowdUp color tokens.
///
/// The accent lives in one place. To switch it, change [accent] and
/// [accentDeep] here and `brand_accent` / `brand_accent_deep` in
/// `android/app/src/main/res/values/colors.xml`.
class ShowdColors {
  ShowdColors._();

  static const ink = Color(0xFF0E0E0C);
  static const carbon = Color(0xFF171714);
  static const graphite = Color(0xFF262622);
  static const graphiteStrong = Color(0xFF3A3A34);
  static const paper = Color(0xFFF2EEE6);
  static const stone = Color(0xFF8F8A80);
  static const missed = Color(0xFF5A5750);

  static const accent = Color(0xFF5CF0BE);
  static const accentDeep = Color(0xFF2A9C77);

  /// Text and glyphs placed on [accent].
  static const onAccent = ink;

  /// Destructive actions only. Never used for a missed day.
  static const alert = Color(0xFFFF6B5E);
}

class ShowdSpace {
  ShowdSpace._();
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s12 = 48.0;

  /// Side padding for every screen.
  static const gutter = 20.0;

  /// Minimum touch target.
  static const touch = 48.0;
}

class ShowdRadius {
  ShowdRadius._();
  static const control = 16.0;
  static const card = 20.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

class ShowdMotion {
  ShowdMotion._();
  static const quick = Duration(milliseconds: 180);
  static const flip = Duration(milliseconds: 450);
  static const takeover = Duration(milliseconds: 600);
  static const hold = Duration(milliseconds: 1200);
  static const flipCurve = Curves.easeOutBack;
  static const settle = Curves.easeOutCubic;
}

/// WCAG relative-luminance contrast ratio between two opaque colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
