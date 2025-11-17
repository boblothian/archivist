// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:archivereader/startup.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';
import 'services/cloud_sync_service.dart';
import 'services/favourites_service.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // 6. Firebase & Cloud Sync can stay fire-and-forget
  unawaited(_startFirebaseAndSync());
}

Future<void> _startFirebaseAndSync() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseFirestore.instance.clearPersistence();
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await CloudSyncService.instance.start(uid: uid);
    }
  } catch (e, s) {
    debugPrint('Firebase/CloudSync failed: $e\n$s');
  }
}
