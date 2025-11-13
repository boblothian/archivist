// lib/theme/app_colours.dart
import 'dart:ui';

/// Core colour definitions for the app.
class AppColours {
  const AppColours._();

  /// Backgrounds for light / dark themes.
  static const lightBg = Color(0xFFF6F5F2);
  static const darkBg = Color(0xFF0E0E12);

  /// Individual seed colours for the palette choices.
  static const seedIndigo = Color(0xFF0B1644); // Original
  static const seedTeal = Color(0xFF0E7C7B);
  static const seedAmber = Color(0xFFB6822B);
  static const seedRose = Color(0xFFB0413E);
  static const seedViolet = Color(0xFF6C3FB1);

  /// List of seed colours used by AppTheme (order matters, index-based).
  static const List<Color> themeSeeds = <Color>[
    seedIndigo,
    seedTeal,
    seedAmber,
    seedRose,
    seedViolet,
  ];

  /// Human-friendly names, same order as [themeSeeds].
  static const List<String> themeSeedNames = <String>[
    'Indigo',
    'Teal',
    'Amber',
    'Rose',
    'Violet',
  ];

  /// Descriptions for each palette, same order as [themeSeeds].
  static const List<String> themeSeedDescriptions = <String>[
    'Default Archivist accent',
    'Cool teal accent',
    'Warm amber accent',
    'Soft rose accent',
    'Deep violet accent',
  ];
}
