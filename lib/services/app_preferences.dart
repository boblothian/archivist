// lib/services/app_preferences.dart
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  static const _kAllowNsfw = 'allow_nsfw';

  /// true  → user turned NSFW on  (i.e. *do NOT* filter)
  /// false → default, SFW mode (filter NSFW)
  Future<bool> get allowNsfw async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAllowNsfw) ?? false;
  }

  Future<void> setAllowNsfw(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowNsfw, value);
  }

  /// Helper used by collection screens
  Future<bool> get sfwOnly async => !(await allowNsfw);
}
