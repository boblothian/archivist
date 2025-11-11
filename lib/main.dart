// lib/main.dart  (updated to init Firebase + anonymous auth + start CloudSync)
import 'dart:async';
import 'dart:io';

import 'package:archivereader/startup.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// NEW
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';
import 'services/cloud_sync_service.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Local storage first
  await _initStorage();

  // 2) Load theme synchronously
  final themeController = await ThemeController.load();

  // 3) Show UI ASAP
  runApp(ArchivistApp(themeController: themeController));

  // 4) Background startup
  unawaited(_safeStartup(themeController));
}

/// Fire-and-forget startup
Future<void> _safeStartup(ThemeController controller) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }

    await Startup.initialize(controller);

    // FIX: Clear Firestore cache on startup to prevent ghost deletes (iOS-specific)
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseFirestore.instance.clearPersistence();
      debugPrint('iOS Firestore cache cleared to prevent sync ghosts');
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await CloudSyncService.instance.start(uid: uid);
    }
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
