// lib/startup.dart
import 'dart:async';

import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Fire-and-forget a future
void _unawaited(Future<void> future) {
  future.catchError((e, s) {
    debugPrint('Background init failed: $e\n$s');
  });
}

class Startup {
  /// `themeController` is **already loaded** – we only trigger other services.
  static Future<void> initialize(ThemeController themeController) async {
    // === NON-BLOCKING INITIALIZATION ===
    _unawaited(
      FavoritesService.instance.init().timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('FavoritesService init timed out'),
      ),
    );

    _unawaited(
      RecentProgressService.instance.init().timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('RecentProgressService init timed out'),
      ),
    );

    // No need to call themeController.load() – it was already done in main.dart

    // === UI SYSTEM SETUP ===
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint('Failed to set immersive mode: $e');
    }
  }
}
