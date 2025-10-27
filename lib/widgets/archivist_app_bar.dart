import 'package:flutter/material.dart';

class ArchivistAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ArchivistAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      centerTitle: true,
      elevation: 0,
      title: Image.asset(
        'assets/images/archivist_banner_logo.png',
        height: 80,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
