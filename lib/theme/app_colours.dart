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
  static const seedForest = Color(0xFF1E5631);
  static const seedSlate = Color(0xFF3A4750);
  static const seedCrimson = Color(0xFF8A1F1F);
  static const seedCobalt = Color(0xFF014F86);
  static const seedBurntOrange = Color(0xFFBB4A04);
  static const seedMint = Color(0xFF00A676);

  static const List<Color> themeSeeds = <Color>[
    seedIndigo,
    seedTeal,
    seedAmber,
    seedRose,
    seedViolet,
    seedForest,
    seedSlate,
    seedCrimson,
    seedCobalt,
    seedBurntOrange,
    seedMint,
  ];

  static const List<String> themeSeedNames = <String>[
    'Indigo',
    'Teal',
    'Amber',
    'Rose',
    'Violet',
    'Forest',
    'Slate',
    'Crimson',
    'Cobalt',
    'Burnt Orange',
    'Mint',
  ];

  static const List<String> themeSeedDescriptions = <String>[
    'Default Archivist accent',
    'Cool teal accent',
    'Warm amber accent',
    'Soft rose accent',
    'Deep violet accent',
    'Natural green',
    'Muted modern grey-blue',
    'Cinematic deep red',
    'Bold blue',
    'Retro VHS orange',
    'Fresh lightweight mint',
  ];
}
