import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// The single ShowdUp theme. Dark only: ink background, one accent.
ThemeData buildShowdTheme() {
  const scheme = ColorScheme.dark(
    surface: ShowdColors.ink,
    onSurface: ShowdColors.paper,
    onSurfaceVariant: ShowdColors.stone,
    surfaceContainerLowest: ShowdColors.ink,
    surfaceContainerLow: ShowdColors.carbon,
    surfaceContainer: ShowdColors.carbon,
    surfaceContainerHigh: ShowdColors.carbon,
    surfaceContainerHighest: ShowdColors.graphite,
    primary: ShowdColors.accent,
    onPrimary: ShowdColors.onAccent,
    primaryContainer: ShowdColors.accentDeep,
    onPrimaryContainer: ShowdColors.paper,
    secondary: ShowdColors.accent,
    onSecondary: ShowdColors.onAccent,
    secondaryContainer: ShowdColors.graphite,
    onSecondaryContainer: ShowdColors.paper,
    tertiary: ShowdColors.accent,
    onTertiary: ShowdColors.onAccent,
    error: ShowdColors.alert,
    onError: ShowdColors.ink,
    outline: ShowdColors.graphiteStrong,
    outlineVariant: ShowdColors.graphite,
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(ShowdRadius.control),
  );
  WidgetStateProperty<Color?> byState({
    required Color selected,
    required Color idle,
  }) => WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected) ? selected : idle,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: ShowdColors.ink,
    canvasColor: ShowdColors.ink,
    fontFamily: ShowdType.text,
    splashFactory: InkRipple.splashFactory,
    splashColor: ShowdColors.paper.withValues(alpha: .06),
    highlightColor: Colors.transparent,
    dividerColor: ShowdColors.graphite,
    textTheme: const TextTheme(
      displayLarge: ShowdType.numeralXL,
      displayMedium: ShowdType.numeralL,
      displaySmall: ShowdType.numeralM,
      headlineLarge: ShowdType.hero,
      headlineMedium: ShowdType.titleXL,
      headlineSmall: ShowdType.titleL,
      titleLarge: ShowdType.titleM,
      titleMedium: ShowdType.bodyL,
      titleSmall: ShowdType.bodyM,
      bodyLarge: ShowdType.bodyL,
      bodyMedium: ShowdType.bodyL,
      bodySmall: ShowdType.bodyM,
      labelLarge: ShowdType.button,
      labelMedium: ShowdType.label,
      labelSmall: ShowdType.caption,
    ),
    iconTheme: const IconThemeData(color: ShowdColors.paper, size: 24),
    appBarTheme: const AppBarTheme(
      backgroundColor: ShowdColors.ink,
      foregroundColor: ShowdColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: ShowdType.titleM,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ShowdColors.accent,
        foregroundColor: ShowdColors.onAccent,
        disabledBackgroundColor: ShowdColors.graphite,
        disabledForegroundColor: ShowdColors.stone,
        minimumSize: const Size.fromHeight(56),
        textStyle: ShowdType.button,
        shape: controlShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ShowdColors.paper,
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: ShowdColors.graphiteStrong),
        textStyle: ShowdType.bodyL,
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ShowdColors.paper,
        minimumSize: const Size(48, 48),
        textStyle: ShowdType.bodyL,
        shape: controlShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ShowdColors.carbon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: ShowdType.label,
      floatingLabelStyle: ShowdType.label,
      hintStyle: ShowdType.bodyL.copyWith(color: ShowdColors.stone),
      helperStyle: ShowdType.caption,
      helperMaxLines: 3,
      errorStyle: ShowdType.caption.copyWith(color: ShowdColors.alert),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ShowdColors.graphiteStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ShowdColors.graphiteStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ShowdColors.accent, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: byState(selected: ShowdColors.ink, idle: ShowdColors.paper),
      trackColor: byState(
        selected: ShowdColors.accent,
        idle: ShowdColors.graphite,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: byState(
        selected: ShowdColors.accent,
        idle: ShowdColors.graphiteStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: byState(
        selected: ShowdColors.accent,
        idle: Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(ShowdColors.ink),
      side: const BorderSide(color: ShowdColors.graphiteStrong, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ShowdColors.accent,
      inactiveTrackColor: ShowdColors.graphite,
      thumbColor: ShowdColors.accent,
      overlayColor: Color(0x225CF0BE),
      trackHeight: 6,
      tickMarkShape: SliderTickMarkShape.noTickMark,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: ShowdColors.ink,
      selectedColor: ShowdColors.accent,
      labelStyle: ShowdType.bodyM.copyWith(color: ShowdColors.paper),
      secondaryLabelStyle: ShowdType.bodyM.copyWith(color: ShowdColors.ink),
      side: const BorderSide(color: ShowdColors.graphiteStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShowdRadius.pill),
      ),
      checkmarkColor: ShowdColors.ink,
      showCheckmark: false,
    ),
    dividerTheme: const DividerThemeData(
      color: ShowdColors.graphite,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: ShowdColors.paper,
      textColor: ShowdColors.paper,
      minVerticalPadding: 12,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ShowdColors.accent,
      linearTrackColor: ShowdColors.graphite,
      circularTrackColor: ShowdColors.graphite,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ShowdColors.carbon,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: ShowdType.titleM,
      contentTextStyle: ShowdType.bodyL.copyWith(color: ShowdColors.stone),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShowdRadius.sheet),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ShowdColors.carbon,
      modalBackgroundColor: ShowdColors.carbon,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: ShowdColors.graphiteStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShowdRadius.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ShowdColors.graphite,
      contentTextStyle: ShowdType.bodyL,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShowdRadius.control),
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: ShowdColors.carbon,
      dialBackgroundColor: ShowdColors.graphite,
      hourMinuteColor: ShowdColors.graphite,
      hourMinuteTextColor: ShowdColors.paper,
      dayPeriodTextColor: ShowdColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShowdRadius.sheet),
      ),
    ),
  );
}
