import 'dart:async';

import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Fire-and-forget a future — prevents uncaught exceptions
void _unawaited(Future<void> future) {
  future.catchError((e, s) {
    debugPrint('Background init failed: $e\n$s');
  });
}

class Startup {
  static Future<void> initialize(ThemeController themeController) async {
    // === NON-BLOCKING INITIALIZATION ===
    // We don't await these — they run in background
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

    _unawaited(
      themeController.load().timeout(
        const Duration(seconds: 2),
        onTimeout: () => debugPrint('Theme load timed out'),
      ),
    );

    // === UI SYSTEM SETUP (safe to do immediately) ===
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint('Failed to set immersive mode: $e');
    }
  }
}
