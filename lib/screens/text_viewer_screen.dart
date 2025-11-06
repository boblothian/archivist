// text_viewer_screen.dart
import 'package:fade_shimmer/fade_shimmer.dart';
import 'package:flutter/material.dart';

import '../utils.dart';

class TextViewerScreen extends StatefulWidget {
  final String url;
  final String? filenameHint;
  final String identifier;
  final String title;

  const TextViewerScreen({
    super.key,
    required this.url,
    this.filenameHint,
    required this.identifier,
    required this.title,
  });

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  String? _content;
  bool _loading = true;
  double _progress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0.0;
    });

    try {
      final text = await fetchTextWithCache(
        url: widget.url,
        filenameHint: widget.filenameHint,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            final p = received / total;
            ifMounted(this, () => setState(() => _progress = p));
          }
        },
      );

      ifMounted(this, () {
        _content = text;
        _loading = false;
      });
    } catch (e) {
      ifMounted(this, () {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          // Shimmer background
          const FadeShimmer(
            width: double.infinity,
            height: double.infinity,
            highlightColor: Color(0xFF424242),
            baseColor: Color(0xFF212121),
            millisecondsDelay: 1500,
          ),

          // Loading content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  _progress == 0
                      ? 'Downloading text...'
                      : '${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.filenameHint != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.filenameHint!.split('/').last,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          _content ?? '',
          style: const TextStyle(
            fontSize: 16,
            fontFamily: 'monospace',
            height: 1.5,
            color: Colors.white,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          _loading || _error != null
              ? null
              : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(widget.title),
                elevation: 0,
              ),
      body: Container(color: Colors.black, child: body),
    );
  }
}
