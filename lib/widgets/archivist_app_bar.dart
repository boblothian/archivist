// lib/archivist_app_bar.dart
import 'package:flutter/material.dart';

/// A clean, theme-aware AppBar with your logo
class ArchivistAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ArchivistAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBar(
      // Respect theme → transparent or surface
      backgroundColor:
          theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: Image.asset(
        'assets/images/archivist_banner_logo.png',
        height: 75,
        fit: BoxFit.contain,
        // Optional: auto-tint logo for dark mode
        // color: isDark ? Colors.white : null,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
