// lib/ui/app.dart
import 'package:archivereader/collection_store.dart';
import 'package:archivereader/theme/app_theme.dart';
import 'package:archivereader/theme/theme_controller.dart';
import 'package:archivereader/ui/splash/app_splash_screen.dart';
import 'package:flutter/material.dart';

class ArchivistApp extends StatelessWidget {
  final ThemeController themeController;

  const ArchivistApp({required this.themeController, super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeControllerProvider(
      controller: themeController,
      child: AnimatedBuilder(
        animation: themeController,
        builder: (_, __) {
          return MaterialApp(
            title: 'Archivist',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeController.mode,
            home: const AppSplashScreen(),
            builder: (context, child) {
              // Wrap in a widget that listens to store changes
              return _CollectionStoreListener(child: child!);
            },
          );
        },
      ),
    );
  }
}

// Hidden listener – rebuilds when store notifies
class _CollectionStoreListener extends StatefulWidget {
  final Widget child;
  const _CollectionStoreListener({required this.child});

  @override
  State<_CollectionStoreListener> createState() =>
      _CollectionStoreListenerState();
}

class _CollectionStoreListenerState extends State<_CollectionStoreListener> {
  @override
  void initState() {
    super.initState();
    CollectionStore().addListener(_rebuild);
  }

  @override
  void dispose() {
    CollectionStore().removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.child;
}
