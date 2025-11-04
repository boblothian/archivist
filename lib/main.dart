// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:archivereader/startup.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Init Hive + ensure app directory exists
  await _initStorage();

  // 2. Create theme controller (fast)
  final themeController = ThemeController();

  // 3. Show UI **immediately**
  runApp(ArchivistApp(themeController: themeController));

  // 4. Run heavy startup in background
  unawaited(_safeStartup(themeController));
}

/// Ensures Hive has a valid directory (prevents fopen errors)
Future<void> _initStorage() async {
  await Hive.initFlutter(); // Sets up Hive in docs dir

  // Ensure app-specific folder exists (optional but safe)
  final docsDir = await getApplicationDocumentsDirectory();
  final appDir = Directory('${docsDir.path}/archivist');
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }
}

/// Fire-and-forget startup
Future<void> _safeStartup(ThemeController controller) async {
  try {
    await Startup.initialize(controller);
  } catch (e, s) {
    debugPrint('Startup failed: $e\n$s');
  }
}
