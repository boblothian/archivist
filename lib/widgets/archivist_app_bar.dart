// lib/widgets/archivist_app_bar.dart
import 'package:archivereader/ui/shell/root_shell.dart';
import 'package:flutter/material.dart';

class ArchivistAppBar extends StatefulWidget implements PreferredSizeWidget {
  const ArchivistAppBar({super.key});

  @override
  ArchivistAppBarState createState() => ArchivistAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class ArchivistAppBarState extends State<ArchivistAppBar> {
  String _pageDesc = '';

  void setPageDesc(String desc) {
    if (_pageDesc != desc) {
      setState(() => _pageDesc = desc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final logoPath =
        isDark
            ? 'assets/images/archivist_banner_logo_inverted.png'
            : 'assets/images/archivist_banner_logo.png';

    // Light mode background (as before)
    final backgroundColor =
        isDark ? theme.colorScheme.surface : const Color(0xFFF6F5F2);

    return AppBar(
      backgroundColor: backgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: null,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          // ---- LOGO (left) – clickable to Home with ripple ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // Switch to Home and ensure Home tab stack is reset to root
                  RootShell.switchToTab(0, resetTargetStack: true);
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Image.asset(
                    logoPath,
                    key: ValueKey(logoPath),
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),

          // ---- PAGE TITLE (right) ----
          if (_pageDesc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                right: 28,
              ), // Increased from 16 → 28
              child: Text(
                _pageDesc,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
