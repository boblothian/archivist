import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../net.dart';
import '../ui/capsule_theme.dart';

class CapsuleThumbCard extends StatelessWidget {
  final String heroTag;
  final String imageUrl;
  final double aspectRatio; // used when fillParent=false
  final BoxFit fit;
  final Widget? topRightOverlay;
  final bool fillParent; // NEW

  const CapsuleThumbCard({
    super.key,
    required this.heroTag,
    required this.imageUrl,
    this.aspectRatio = 3 / 4,
    this.fit = BoxFit.contain,
    this.topRightOverlay,
    this.fillParent = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Stack(
      children: [
        Positioned.fill(
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              httpHeaders: Net.headers,
              imageUrl: imageUrl,
              fit: fit,
              placeholder:
                  (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              errorWidget:
                  (context, url, error) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
        if (topRightOverlay != null)
          Positioned(top: 8, right: 8, child: topRightOverlay!),
      ],
    );

    return Container(
      decoration: capsuleDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kCapsuleRadius),
        child:
            fillParent
                ? SizedBox.expand(
                  child: child,
                ) // fills whatever height the parent gives
                : AspectRatio(aspectRatio: aspectRatio, child: child),
      ),
    );
  }
}
