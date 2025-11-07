// lib/widgets/long_press_favorite_target.dart
// Ensure init() is awaited before opening the picker.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/favourites_service.dart';
import 'favourite_add_dialogue.dart';

class LongPressFavoriteTarget extends StatelessWidget {
  final Widget child;
  final FavoriteItem item;
  final VoidCallback? onAdded;

  const LongPressFavoriteTarget({
    super.key,
    required this.child,
    required this.item,
    this.onAdded,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () async {
        HapticFeedback.mediumImpact();
        try {
          await FavoritesService.instance.init(); // ✅ make sure box is ready
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Favourites init failed: $e')));
          return;
        }
        final folder = await showAddToFavoritesDialog(context, item: item);
        if (folder != null && context.mounted) {
          onAdded?.call();
        }
      },
      child: child,
    );
  }
}
