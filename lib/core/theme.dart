import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// Legacy token names kept for older call sites. New code uses ShowdColors.
class T {
  T._();
  static const bg = ShowdColors.ink;
  static const surface = ShowdColors.carbon;
  static const surfaceRaised = ShowdColors.graphite;
  static const outline = ShowdColors.graphiteStrong;
  static const text = ShowdColors.paper;
  static const muted = ShowdColors.stone;
  static const accent = ShowdColors.accent;
  static const accentSoft = ShowdColors.accent;
  static const danger = ShowdColors.alert;
  static const ok = ShowdColors.accent;
  static const radius = ShowdRadius.card;
}

ThemeData buildTheme() => buildShowdTheme();
