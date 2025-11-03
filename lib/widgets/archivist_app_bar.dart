// lib/widgets/archivist_app_bar.dart
import 'package:flutter/material.dart';

class ArchivistAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ArchivistAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final logo =
        isDark
            ? 'assets/images/archivist_banner_logo_inverted.png'
            : 'assets/images/archivist_banner_logo.png';

    // Use custom color only in light mode
    final backgroundColor =
        isDark ? theme.colorScheme.surface : const Color(0xFFF6F5F2);

    return AppBar(
      backgroundColor: backgroundColor,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Image.asset(
          logo,
          key: ValueKey(logo),
          height: 56,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
