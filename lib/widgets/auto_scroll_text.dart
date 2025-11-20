import 'package:flutter/material.dart';

class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration pause;
  final Duration? duration; // if null, auto-calculated from text width

  const AutoScrollText({
    super.key,
    required this.text,
    this.style,
    this.pause = const Duration(milliseconds: 800),
    this.duration,
  });

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollCtrl;
  late final AnimationController _animCtrl;
  Animation<double>? _animation;
  double _maxScrollExtent = 0;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _animCtrl = AnimationController(vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  @override
  void didUpdateWidget(covariant AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
    }
  }

  Future<void> _setup() async {
    if (!mounted || !_scrollCtrl.hasClients) return;

    await Future.delayed(const Duration(milliseconds: 10)); // let layout settle

    final max = _scrollCtrl.position.maxScrollExtent;
    _maxScrollExtent = max;
    _needsScroll = max > 0;

    if (!_needsScroll) {
      _animCtrl.stop();
      if (_scrollCtrl.positions.isNotEmpty) {
        _scrollCtrl.jumpTo(0);
      }
      return;
    }

    // Duration based on distance, clamped for sanity.
    final duration =
        widget.duration ??
        Duration(milliseconds: (max * 20).clamp(3000, 15000).toInt());

    _animCtrl
      ..stop()
      ..reset()
      ..duration = duration;

    _animation = Tween<double>(begin: 0, end: _maxScrollExtent).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    )..addListener(() {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_animation!.value);
    });

    // Small pause, then start bouncing back and forth.
    await Future.delayed(widget.pause);
    if (!mounted) return;

    _animCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
