// lib/startup.dart
import 'dart:async';

import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fire-and-forget with error logging
void _unawaited(Future<void> f) {
  f.catchError((e, s) => debugPrint('Background init failed: $e\n$s'));
}

class Startup {
  /// Theme is preloaded in main.dart; here we only kick off background services and UI system setup.
  static Future<void> initialize(ThemeController _themeController) async {
    // Defer heavy I/O until after first frame to keep first paint snappy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unawaited(_initFavorites());
      _unawaited(_initRecent());
    });

    // UI system setup (guarded)
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint('Failed to set immersive mode: $e');
    }
  }

  static Future<void> _initFavorites() async {
    try {
      await FavoritesService.instance.init().timeout(
        const Duration(seconds: 5),
      );
      debugPrint('FavoritesService: ready');
    } on TimeoutException {
      debugPrint('FavoritesService init timed out');
    } catch (e, s) {
      debugPrint('FavoritesService init error: $e\n$s');
    }
  }

  static Future<void> _initRecent() async {
    try {
      await RecentProgressService.instance.init().timeout(
        const Duration(seconds: 5),
      );
      debugPrint('RecentProgressService: ready');
    } on TimeoutException {
      debugPrint('RecentProgressService init timed out');
    } catch (e, s) {
      debugPrint('RecentProgressService init error: $e\n$s');
    }
  }
}
