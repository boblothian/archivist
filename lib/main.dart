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

  // Create theme controller (fast) – needed before first frame
  final themeController = ThemeController();

  // Show UI **immediately** – no blocking work
  runApp(ArchivistApp(themeController: themeController));

  // Run heavy startup in background (including storage init)
  unawaited(_safeStartup(themeController));
}

/// Fire-and-forget startup
Future<void> _safeStartup(ThemeController controller) async {
  try {
    // ---- DEFERRED STORAGE INITIALISATION ---------------------------------
    await _initStorage();
    await Startup.initialize(controller);
  } catch (e, s) {
    debugPrint('Startup failed: $e\n$s');
  }
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
