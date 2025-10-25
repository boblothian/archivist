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
        final folder = await showAddToFavoritesDialog(context, item: item);
        if (folder != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Added to "$folder"')));
          onAdded?.call();
        }
      },
      child: child,
    );
  }
}
