import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../net.dart';

class ImageViewerScreen extends StatelessWidget {
  final List<String> imageUrls;

  const ImageViewerScreen({super.key, required this.imageUrls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Viewer')),
      body: PageView.builder(
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          final url = imageUrls[index];
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: CachedNetworkImage(
                imageUrl: url,
                httpHeaders: Net.headers,
                fit: BoxFit.contain,
                progressIndicatorBuilder:
                    (context, url, progress) =>
                        const Center(child: CircularProgressIndicator()),
                errorWidget:
                    (context, url, error) =>
                        const Icon(Icons.broken_image, size: 64),
              ),
            ),
          );
        },
      ),
    );
  }
}
