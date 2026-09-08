import 'package:flutter/material.dart';

/// FROZEN CONTRACT: design tokens.
class T {
  T._();
  static const bg = Color(0xFF0D1426);
  static const surface = Color(0xFF16203A);
  static const text = Color(0xFFF5F0E6);
  static const muted = Color(0xFFAAB4C8);
  static const accent = Color(0xFFFF8A4C);
  static const danger = Color(0xFFFF5C5C);
  static const ok = Color(0xFF4CD9A0);
  static const radius = 20.0;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: T.bg,
    primary: T.accent,
    secondary: T.ok,
    error: T.danger,
    onSurface: T.text,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: T.bg,
    fontFamily: 'Inter',
    cardTheme: CardThemeData(
      color: T.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(T.radius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: T.accent,
        foregroundColor: T.bg,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.radius),
        ),
      ),
    ),
  );
}
