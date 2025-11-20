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
// ⬇️ Add this import
import 'services/playback_manager.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⚠️ Critical for iOS background/AirPlay video
  await PlaybackManager.configureAudioSessionOnce();

  // 🔊 Background audio / lock-screen controls (safe to keep)
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.robertlothian.archivereader.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  await _clearAppCache();

  await Hive.initFlutter();
  final docsDir = await getApplicationDocumentsDirectory();
  final appDir = Directory('${docsDir.path}/archivist');
  if (!await appDir.exists()) await appDir.create(recursive: true);

  await FavoritesService.instance.init();
  final themeController = await ThemeController.load();
  await Startup.initialize(themeController);

  runApp(ArchivistApp(themeController: themeController));
}

Future<void> _clearAppCache() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  } catch (_) {
    // ignore
  }
}
