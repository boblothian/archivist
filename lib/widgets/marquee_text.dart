// lib/widgets/marquee_text.dart
import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration scrollDuration;
  final Duration pauseDuration;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.scrollDuration = const Duration(seconds: 8),
    this.pauseDuration = const Duration(seconds: 2),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _scrollController = ScrollController();
  bool _needsMarquee = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _needsMarquee = false;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
    }
  }

  void _evaluate() {
    if (!mounted || widget.text.isEmpty) return;

    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout();

    // Prefer the actual rendered width of this widget (works properly inside AppBar/title)
    double availableWidth;

    final renderObj = context.findRenderObject();
    if (renderObj is RenderBox && renderObj.hasSize) {
      availableWidth = renderObj.size.width;
    } else {
      // Fallback (old behaviour) — approximate available width from screen size.
      // Keep some default padding similar to your previous '-140' heuristic.
      availableWidth = MediaQuery.of(context).size.width - 140;
    }

    // Ensure availableWidth is positive
    availableWidth = availableWidth.clamp(0.0, double.infinity);

    final bool shouldScroll = painter.width > availableWidth;

    if (shouldScroll != _needsMarquee) {
      setState(() => _needsMarquee = shouldScroll);
    }

    // Always (re)start scrolling when needed — even if controller not attached yet
    if (shouldScroll) {
      _startOrRestartScrolling(painter.width);
    }
  }

  void _startOrRestartScrolling(double textWidth) {
    // Reset to start
    try {
      _scrollController.jumpTo(0);
    } catch (_) {}

    // Wait until the ScrollView is attached, then start
    if (_scrollController.hasClients) {
      // Start after a frame to allow the child to layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _doScroll(textWidth);
        }
      });
    } else {
      // If not attached yet (very common in AppBar), wait one frame and try again
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _doScroll(textWidth);
        } else if (mounted) {
          // If still not attached, try again next frame
          WidgetsBinding.instance.addPostFrameCallback((__) {
            if (mounted && _scrollController.hasClients) {
              _doScroll(textWidth);
            }
          });
        }
      });
    }
  }

  void _doScroll(double textWidth) async {
    if (!mounted || !_scrollController.hasClients) return;

    const double gap = 120.0;
    final childWidth = textWidth + gap;

    // We'll try to use the controller's real values. If they're not ready yet,
    // we'll wait a few frames for layout (using endOfFrame) and then compute.
    double distance = 0;
    const int maxRetries = 8;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      try {
        final pos = _scrollController.position;
        final viewport = pos.viewportDimension;
        final maxExtent =
            pos.maxScrollExtent; // should equal childWidth - viewport

        // If viewport is positive, compute the desired distance (child - viewport).
        final desired = (childWidth - viewport).clamp(0.0, double.infinity);

        // Prefer the authoritative maxExtent if it's > 0, otherwise use computed desired.
        if (maxExtent > 0) {
          distance = maxExtent;
        } else if (viewport > 0) {
          distance = desired;
        }
        // If we've got a positive distance, break and use it.
        if (distance > 0) break;
      } catch (_) {
        // ignore and retry
      }

      // Wait until next frame for layout to settle.
      await WidgetsBinding.instance.endOfFrame;
    }

    // As a final fallback, compute distance from screen width (least accurate).
    if (distance <= 0) {
      final fallbackViewport = MediaQuery.of(context).size.width;
      distance = (childWidth - fallbackViewport).clamp(0.0, double.infinity);
    }

    // If there's nothing to scroll, bail out.
    if (distance <= 0) return;

    final Duration dur = widget.scrollDuration;

    // Forward to end
    try {
      await _scrollController.animateTo(
        distance,
        duration: dur,
        curve: Curves.linear,
      );
    } catch (_) {
      return;
    }

    if (!mounted || !_scrollController.hasClients) return;
    await Future.delayed(widget.pauseDuration);

    // Back to start
    try {
      await _scrollController.animateTo(0, duration: dur, curve: Curves.linear);
    } catch (_) {
      return;
    }

    if (!mounted || !_scrollController.hasClients) return;
    await Future.delayed(widget.pauseDuration);

    if (mounted) _doScroll(textWidth);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsMarquee) {
      return Text(
        widget.text,
        style: widget.style,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _scrollController,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: [
                Text(widget.text, style: widget.style),
                const SizedBox(width: 120),
              ],
            ),
          ),
        );
      },
    );
  }
}
