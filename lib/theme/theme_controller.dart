// lib/theme/theme_controller.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Controls the app's [ThemeMode] and the selected seed palette.
///
/// Usage:
///   final c = ThemeControllerProvider.of(context).controller;
///   c.setMode(ThemeMode.dark);
///   c.setSeedIndex(3);
class ThemeController with ChangeNotifier {
  ThemeController._(this._mode, this._seedIndex) {
    // Ensure AppTheme picks up the stored values
    AppTheme.setSeedIndex(_seedIndex);
  }

  static const _kThemeModeKey = 'theme_mode';
  static const _kSeedIndexKey = 'theme_seed_index';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  int _seedIndex;
  int get seedIndex => _seedIndex;

  /// Load saved theme settings from storage.
  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedMode = prefs.getString(_kThemeModeKey);
    final ThemeMode mode =
        savedMode == null
            ? ThemeMode.system
            : ThemeMode.values.firstWhere(
              (e) => e.toString() == savedMode,
              orElse: () => ThemeMode.system,
            );

    final int seedIndex = prefs.getInt(_kSeedIndexKey) ?? 0;

    return ThemeController._(mode, seedIndex);
  }

  /// Change the theme mode (system / light / dark) and persist.
  Future<void> setMode(ThemeMode newMode) async {
    if (newMode == _mode) return;

    _mode = newMode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, newMode.toString());
  }

  /// Change which seed palette is active and persist.
  Future<void> setSeedIndex(int index) async {
    if (index == _seedIndex) return;

    _seedIndex = index;
    AppTheme.setSeedIndex(index);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedIndexKey, index);
  }
}

/// InheritedWidget wrapper for the [ThemeController].
class ThemeControllerProvider extends InheritedWidget {
  const ThemeControllerProvider({
    super.key,
    required this.controller,
    required super.child,
  });

  final ThemeController controller;

  static ThemeControllerProvider of(BuildContext context) {
    final ThemeControllerProvider? result =
        context.dependOnInheritedWidgetOfExactType<ThemeControllerProvider>();
    assert(result != null, 'No ThemeControllerProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(covariant ThemeControllerProvider oldWidget) {
    return controller != oldWidget.controller;
  }
}
