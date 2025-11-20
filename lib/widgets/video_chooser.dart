// ===============================
// 1) lib/widgets/video_chooser.dart
// ===============================
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../media/media_player_ops.dart';
import '../services/recent_progress_service.dart';
import '../utils/archive_helpers.dart';

class ArchiveVideoMeta {
  final String name;
  final String format;
  final int? width;
  final int? height;
  final int? sizeBytes;

  const ArchiveVideoMeta({
    required this.name,
    required this.format,
    this.width,
    this.height,
    this.sizeBytes,
  });

  factory ArchiveVideoMeta.fromMap(Map<String, dynamic> m) {
    // Parse size: raw bytes (e.g. "9234567") OR formatted (e.g. "9.2 MB")
    int? parseSize(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;

      // Try direct parse first (raw bytes)
      final direct = int.tryParse(s);
      if (direct != null) return direct;

      // Try parsing formatted size: "9.2 MB", "1.5 GB", etc.
      final match = RegExp(
        r'^([\d.]+)\s*(B|KB|MB|GB|TB)$',
        caseSensitive: false,
      ).firstMatch(s);
      if (match == null) return null;

      final double value = double.tryParse(match.group(1)!) ?? 0;
      final String unit = match.group(2)!.toUpperCase();

      final units = {'B': 0, 'KB': 1, 'MB': 2, 'GB': 3, 'TB': 4};
      final int multiplier = units[unit] ?? 0;
      return (value * (1 << (10 * multiplier))).round();
    }

    return ArchiveVideoMeta(
      name: (m['name'] ?? '').toString(),
      format:
          (m['format'] ?? m['fmt'] ?? '').toString(), // Support legacy 'fmt'
      width: _toInt(m['width']),
      height: _toInt(m['height']),
      sizeBytes: parseSize(m['size']),
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }
}

String _humanBytes(int? b) {
  if (b == null || b <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = b.toDouble();
  int u = 0;
  while (size >= 1024 && u < units.length - 1) {
    size /= 1024;
    u++;
  }
  final fixed = size < 10 ? size.toStringAsFixed(1) : size.toStringAsFixed(0);
  return u == 0 ? '$b ${units[u]}' : '$fixed ${units[u]}';
}

String _prettyFilename(String raw) {
  var s = raw;
  s = s.replaceFirst(
    RegExp(r'\.(mp4|mkv|webm|mov|m4v|avi|m3u8)$', caseSensitive: false),
    '',
  );
  s = s.replaceFirst(RegExp(r'\.ia$', caseSensitive: false), '');
  s = s.replaceAll('_', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

String _extFromName(String name) {
  final m = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(name);
  return (m?.group(1) ?? '').toLowerCase();
}

String _guessMime(String name, String format) {
  final n = name.toLowerCase();
  final f = format.toLowerCase();
  if (n.endsWith('.webm') || f.contains('webm')) return 'video/webm';
  if (n.endsWith('.mp4') ||
      n.endsWith('.m4v') ||
      f.contains('mp4') ||
      f.contains('h.264'))
    return 'video/mp4';
  if (n.endsWith('.mkv') || f.contains('matroska')) return 'video/x-matroska';
  if (n.endsWith('.mov')) return 'video/quicktime';
  if (n.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
  return 'video/*';
}

String _resolutionLabel(ArchiveVideoMeta m) {
  if (m.width != null && m.height != null) return '${m.width}x${m.height}';
  final nameRes = RegExp(r'(\d{3,4})p').firstMatch(m.name)?.group(1);
  if (nameRes != null) return '${nameRes}p';
  return 'Unknown';
}

class _AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration pause;
  final Duration? duration; // if null, auto-calculated from text width

  const _AutoScrollText({
    Key? key,
    required this.text,
    this.style,
    this.pause = const Duration(milliseconds: 800),
    this.duration,
  }) : super(key: key);

  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText>
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
  void didUpdateWidget(covariant _AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
    }
  }

  Future<void> _setup() async {
    if (!mounted || !_scrollCtrl.hasClients) return;

    await Future.delayed(const Duration(milliseconds: 10)); // layout settle

    final max = _scrollCtrl.position.maxScrollExtent;
    _maxScrollExtent = max;
    _needsScroll = max > 0;

    if (!_needsScroll) {
      _animCtrl.stop();
      _scrollCtrl.jumpTo(0);
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

    // Small pause at start, then start bouncing back and forth.
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
          overflow: TextOverflow.visible, // let it overflow so we can scroll it
        ),
      ),
    );
  }
}

Future<void> showVideoChooser(
  BuildContext context, {
  required String identifier,
  required String title,
  required List<dynamic> files,
}) async {
  final options =
      files
          .map(
            (f) =>
                f is ArchiveVideoMeta
                    ? f
                    : ArchiveVideoMeta.fromMap(f as Map<String, dynamic>),
          )
          .where((m) => m.name.isNotEmpty)
          .toList();

  if (options.isEmpty) {
    await launchUrl(
      Uri.parse('https://archive.org/details/$identifier'),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  int resScore(ArchiveVideoMeta m) {
    final s = RegExp(r'(\d{3,4})p').firstMatch(m.name)?.group(1);
    final inferred = int.tryParse(s ?? '') ?? (m.height ?? 0);
    return inferred;
  }

  // Sort by resolution (desc), then size (desc)
  options.sort((a, b) {
    final r = resScore(b).compareTo(resScore(a));
    if (r != 0) return r;
    return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
  });

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final media = MediaQuery.of(sheetCtx);
      const double kItemExtent = 72;
      const double kChrome = 24 + 16 + 16;
      final double desired = (options.length * kItemExtent) + kChrome;
      final double maxH = media.size.height * 0.85;
      const double minH = 200;
      final double height = desired.clamp(minH, maxH);
      final bool scrollable = desired > height + 1;

      return SafeArea(
        child: SizedBox(
          height: height,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            shrinkWrap: true,
            physics:
                scrollable
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
            itemBuilder: (_, i) {
              final op = options[i];
              final res = _resolutionLabel(op);
              final size = _humanBytes(op.sizeBytes);
              final pretty = _prettyFilename(op.name);

              final rawFmt = (op.format).trim();
              final ext = _extFromName(op.name);
              final fmtLabel = (rawFmt.isNotEmpty ? rawFmt : ext).toUpperCase();

              final url =
                  'https://archive.org/download/$identifier/${Uri.encodeComponent(op.name)}';

              return ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: _AutoScrollText(
                  text: pretty.isEmpty ? op.name : pretty,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                subtitle: _AutoScrollText(
                  text: '$fmtLabel  •  $res  •  $size',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () async {
                  final url =
                      'https://archive.org/download/$identifier/${Uri.encodeComponent(op.name)}';

                  try {
                    await RecentProgressService.instance.touch(
                      id: identifier,
                      title: title,
                      thumb: archiveThumbUrl(identifier),
                      kind: 'video',
                      fileUrl: url,
                      fileName: op.name,
                    );
                  } catch (_) {}

                  await MediaPlayerOps.playVideo(
                    context,
                    url: url,
                    identifier: identifier,
                    title: title,
                  );

                  if (Navigator.canPop(sheetCtx)) {
                    Navigator.pop(sheetCtx);
                  }
                },
              );
            },
          ),
        ),
      );
    },
  );
}
