// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colours.dart' as AppColours;

class AppTheme {
  // -----------------------------------------------------------------------
  // Public entry points – used by the root MaterialApp
  // -----------------------------------------------------------------------
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  // -----------------------------------------------------------------------
  // Private builder
  // -----------------------------------------------------------------------
  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Custom surface colour from app_colours.dart
    final customSurface = isDark ? AppColours.darkBg : AppColours.lightBg;

    // Base M3 colour scheme
    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColours.seed,
      brightness: brightness,
    );

    // Override only the surface colour (background is deprecated)
    final scheme = baseScheme.copyWith(
      surface: customSurface,
      // surfaceContainer can stay the generated one – it will be a shade above customSurface
    );

    final inter = GoogleFonts.interTextTheme();
    final merri = GoogleFonts.merriweatherTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: customSurface, // matches AppBar surface
      textTheme: inter
          .merge(merri)
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      primaryTextTheme: inter.apply(
        bodyColor: scheme.onPrimary,
        displayColor: scheme.onPrimary,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: customSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: inter.bodySmall?.copyWith(
          // withOpacity → withValues
          color: scheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        color: scheme.surface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        iconTheme: WidgetStateProperty.all(
          IconThemeData(color: scheme.onSurface),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
