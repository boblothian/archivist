// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:archivereader/startup.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import 'services/favourites_service.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔊 Initialize background audio / lock-screen controls
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.robertlothian.archivereader.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  // 🧹 Clear temp/cache directory on every app start
  await _clearAppCache();

  // 1. Hive + app directory
  await Hive.initFlutter();
  final docsDir = await getApplicationDocumentsDirectory();
  final appDir = Directory('${docsDir.path}/archivist');
  if (!await appDir.exists()) await appDir.create(recursive: true);

  // 2. Ensure FavoritesService is fully initialized before anything reads it
  await FavoritesService.instance.init();

  // 3. Load theme
  final themeController = await ThemeController.load();

  // 4. Run other startup logic that may depend on Hive / favorites
  await Startup.initialize(themeController);

  // 5. NOW it's safe to start the UI
  runApp(ArchivistApp(themeController: themeController));
}

// Deletes the OS temp directory used by things like downloadWithCache()
// (if that uses getTemporaryDirectory under the hood).
Future<void> _clearAppCache() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  } catch (_) {
    // Swallow errors – failing to clear cache shouldn't block app startup.
  }
}
