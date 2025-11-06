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

  // --------------------------------------------------------------
  // 1. Load theme controller **before** first frame
  // --------------------------------------------------------------
  final themeController = await ThemeController.load();

  // --------------------------------------------------------------
  // 2. Show UI immediately – theme is already loaded
  // --------------------------------------------------------------
  runApp(ArchivistApp(themeController: themeController));

  // --------------------------------------------------------------
  // 3. Run the rest of startup in background
  // --------------------------------------------------------------
  unawaited(_safeStartup(themeController));
}

/// Fire-and-forget startup
Future<void> _safeStartup(ThemeController controller) async {
  try {
    await _initStorage();
    await Startup.initialize(controller);
  } catch (e, s) {
    debugPrint('Startup failed: $e\n$s');
  }
}

/// Ensures Hive has a valid directory
Future<void> _initStorage() async {
  await Hive.initFlutter();

  final docsDir = await getApplicationDocumentsDirectory();
  final appDir = Directory('${docsDir.path}/archivist');
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }
}
