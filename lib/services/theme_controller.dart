import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemePref = 'app_theme_mode'; // 'system' | 'light' | 'dark'

class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kThemePref);
    switch (s) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final str = switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setString(_kThemePref, str);
  }
}

/// Simple provider so we don't need a package.
class ThemeControllerProvider extends InheritedNotifier<ThemeController> {
  const ThemeControllerProvider({
    super.key,
    required ThemeController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  static ThemeController of(BuildContext context) {
    final p =
        context.dependOnInheritedWidgetOfExactType<ThemeControllerProvider>();
    assert(p != null, 'ThemeControllerProvider not found in context');
    return p!.notifier!;
  }
}
