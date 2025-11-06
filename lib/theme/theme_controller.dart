// lib/theme/theme_controller.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The actual controller that holds the current ThemeMode and persists it.
class ThemeController with ChangeNotifier {
  ThemeController._(this._mode);

  static const _kThemeModeKey = 'theme_mode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// Change the theme and persist the choice.
  Future<void> setMode(ThemeMode newMode) async {
    if (newMode == _mode) return;
    _mode = newMode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, newMode.toString());
  }

  /// Load the persisted theme (defaults to system).
  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeModeKey);
    final mode =
        saved == null
            ? ThemeMode.system
            : ThemeMode.values.firstWhere(
              (e) => e.toString() == saved,
              orElse: () => ThemeMode.system,
            );
    return ThemeController._(mode);
  }
}

/// InheritedWidget that makes the controller available everywhere.
class ThemeControllerProvider extends InheritedNotifier<ThemeController> {
  const ThemeControllerProvider({
    required ThemeController controller,
    required Widget child,
    super.key,
  }) : super(notifier: controller, child: child);

  /// Convenience getter used in SettingsScreen.
  static ThemeControllerProvider of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeControllerProvider>();
    assert(provider != null, 'No ThemeControllerProvider found in context');
    return provider!;
  }

  /// Helper to get the controller directly (the way SettingsScreen expects).
  ThemeController get controller => notifier!;
}
