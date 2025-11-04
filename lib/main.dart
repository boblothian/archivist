// lib/main.dart
import 'package:archivereader/startup.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  runApp(ArchivistApp(themeController: themeController));

  await Hive.initFlutter();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _safeStartup(themeController);
  });
}

Future<void> _safeStartup(ThemeController controller) async {
  // Move init logic to services or startup.dart
  await Startup.initialize(controller);
}
