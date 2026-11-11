import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the Material theme from DevPulse tokens. Dark is the default experience.
ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? DpPalette.dark : DpPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.cyan,
    onPrimary: p.onAccent,
    secondary: p.violet,
    onSecondary: Colors.white,
    error: p.critical,
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.fg,
    onSurfaceVariant: p.fgMuted,
    outline: p.line,
    outlineVariant: p.line,
    surfaceContainerLowest: p.canvas,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
  );

  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: p.fg, displayColor: p.fg);
  final radiusMd = BorderRadius.circular(DpRadius.md);

  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    extensions: [p],
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 22),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 22 / 15),
      bodySmall: text.bodySmall?.copyWith(color: p.fgMuted, fontSize: 13),
      labelSmall: text.labelSmall?.copyWith(letterSpacing: 0.2, color: p.fgMuted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.canvas,
      foregroundColor: p.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DpRadius.lg),
        side: BorderSide(color: p.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: DpSpace.md, vertical: DpSpace.md),
      border: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: p.cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: p.critical),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: p.critical, width: 1.5),
      ),
      labelStyle: TextStyle(color: p.fgMuted),
      hintStyle: TextStyle(color: p.fgSubtle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: p.fg,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.cyan.withValues(alpha: 0.16),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.fg : p.fgMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.cyan : p.fgMuted),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.cyan.withValues(alpha: 0.16),
      selectedIconTheme: IconThemeData(color: p.cyan),
      unselectedIconTheme: IconThemeData(color: p.fgMuted),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.fgMuted, minVerticalPadding: DpSpace.md),
    // Filter chips use the DevPulse accent, not Material's default secondary container.
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.cyan.withValues(alpha: 0.18),
      checkmarkColor: p.cyan,
      side: BorderSide(color: p.line),
      labelStyle: TextStyle(color: p.fg, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DpRadius.sm)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.cyan.withValues(alpha: 0.18) : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.all(p.fg),
        side: WidgetStateProperty.all(BorderSide(color: p.line)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.raised,
      contentTextStyle: TextStyle(color: p.fg),
    ),
  );
}
