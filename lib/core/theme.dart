import 'package:flutter/material.dart';

/// FROZEN CONTRACT: design tokens.
class T {
  T._();
  // Near-black and warm parchment borrow the calm contrast of Cursor while
  // the butter, olive and alert-red accents keep ShowdUp's pet expressive.
  static const bg = Color(0xFF080907);
  static const surface = Color(0xFF131410);
  static const surfaceRaised = Color(0xFF1C1D18);
  static const outline = Color(0xFF2D2E27);
  static const text = Color(0xFFF5F0E6);
  static const muted = Color(0xFFA6A197);
  static const accent = Color(0xFFF3C676);
  static const accentSoft = Color(0xFFFFE7B0);
  static const danger = Color(0xFFF05A56);
  static const ok = Color(0xFFA9BE8A);
  static const radius = 20.0;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: T.surface,
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
    dividerColor: T.outline,
    splashColor: T.accent.withValues(alpha: .08),
    highlightColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: T.bg,
      foregroundColor: T.text,
      centerTitle: false,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: T.surface,
      indicatorColor: T.accent.withValues(alpha: .14),
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? T.accent : T.muted,
          size: 22,
        ),
      ),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: T.surfaceRaised,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: T.outline),
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
        foregroundColor: T.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: T.outline),
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
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: T.accent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: T.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: T.surfaceRaised,
      contentTextStyle: const TextStyle(color: T.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
