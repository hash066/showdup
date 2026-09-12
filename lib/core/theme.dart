import 'package:flutter/material.dart';

/// FROZEN CONTRACT: design tokens.
class T {
  T._();
  // Core palette: ink navy, warm ivory, sunrise orange. Status colors are
  // functional feedback rather than additional brand colors.
  static const bg = Color(0xFF0B1220);
  static const surface = Color(0xFF151F2E);
  static const text = Color(0xFFF7F3EA);
  static const muted = Color(0xFF9AA8B9);
  static const accent = Color(0xFFFFB45A);
  static const danger = Color(0xFFFF5C5C);
  static const ok = Color(0xFF4CD9A0);
  static const radius = 16.0;
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
    appBarTheme: const AppBarTheme(
      backgroundColor: T.bg,
      foregroundColor: T.text,
      centerTitle: false,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: T.bg,
      indicatorColor: T.accent.withValues(alpha: .15),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: T.surface,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: T.accent),
      ),
      labelStyle: const TextStyle(color: T.muted, fontSize: 13),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide(color: T.muted.withValues(alpha: .25)),
      ),
    ),
    cardTheme: CardThemeData(
      color: T.surface,
      elevation: 0,
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
