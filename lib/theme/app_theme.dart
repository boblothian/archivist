// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colours.dart';

/// Builds the light / dark [ThemeData] for the app, driven by a seed colour.
/// The seed colour is chosen by an index provided via [setSeedIndex].
class AppTheme {
  AppTheme._();

  /// Index into [AppColours.themeSeeds] for the actively selected seed.
  static int _seedIndex = 0;

  static int get seedIndex => _seedIndex;

  /// Set the active seed index (defensive clamp to valid range).
  static void setSeedIndex(int index) {
    if (AppColours.themeSeeds.isEmpty) {
      _seedIndex = 0;
      return;
    }
    if (index < 0) index = 0;
    if (index >= AppColours.themeSeeds.length) {
      index = AppColours.themeSeeds.length - 1;
    }
    _seedIndex = index;
  }

  /// Light theme getter.
  static ThemeData get light => _build(Brightness.light);

  /// Dark theme getter.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    final seedColor =
        AppColours.themeSeeds.isEmpty
            ? const Color(0xFF0B1644)
            : AppColours.themeSeeds[_seedIndex];

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    final baseTextTheme = GoogleFonts.interTextTheme();
    final textTheme = baseTextTheme.apply(
      bodyColor: colorScheme.onBackground,
      displayColor: colorScheme.onBackground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isLight ? AppColours.lightBg : AppColours.darkBg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      // Your Flutter version wants CardThemeData here.
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6.0),
      ),
      listTileTheme: ListTileThemeData(iconColor: colorScheme.primary),
      switchTheme: const SwitchThemeData(),
      radioTheme: const RadioThemeData(),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.5,
        space: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
