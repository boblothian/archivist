// lib/startup.dart  (unchanged except: ensure services init happens; CloudSync runs after auth in main)
import 'dart:async';

import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

void _unawaited(Future<void> future) {
  future.catchError((e, s) {
    debugPrint('Background init failed: $e\n$s');
  });
}

class Startup {
  static Future<void> initialize(ThemeController themeController) async {
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

    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }
}
