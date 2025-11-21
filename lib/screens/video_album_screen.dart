// lib/screens/video_album_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../media/media_player_ops.dart';
import '../services/recent_progress_service.dart';
import '../services/thumb_override_service.dart';
import '../utils/archive_helpers.dart';

class VideoAlbumScreen extends StatefulWidget {
  final String identifier;
  final String title;

  /// expects {"name": ...}
  final List<Map<String, String>> files;
  final String? thumbUrl;

  /// Optional label like "MP4", "MKV", etc. (used when coming from a format chooser)
  final String? formatLabel;

  const VideoAlbumScreen({
    super.key,
    required this.identifier,
    required this.title,
    required this.files,
    this.thumbUrl,
    this.formatLabel,
  });

  @override
  State<VideoAlbumScreen> createState() => _VideoAlbumScreenState();
}

/// Simple horizontally swipeable text, clipped so it doesn't overflow the tile.
class _SwipeScrollText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _SwipeScrollText({Key? key, required this.text, this.style})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}

class _VideoAlbumScreenState extends State<VideoAlbumScreen> {
  late List<Map<String, String>> _videos;

  @override
  void initState() {
    super.initState();
    _videos = List<Map<String, String>>.from(widget.files);
    _sortVideos();
  }

  bool _isVideoName(String name) {
    final ext = p.extension(name).toLowerCase();
    return [
      '.mp4',
      '.m4v',
      '.mkv',
      '.webm',
      '.mov',
      '.avi',
      '.m3u8',
    ].contains(ext);
  }

  // ---------- NEW HELPERS TO STRIP COLLECTION NAME ----------

  /// Normalize for loose comparison.
  String _normalizeForCompare(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  /// Remove album/collection name prefix if present.
  String _stripAlbumNamePrefix(String rawTitle) {
    final album = widget.title;
    if (album.isEmpty) return rawTitle;

    final albumNorm = _normalizeForCompare(album);
    var result = rawTitle;

    // Case 1: "Album Name/Something"
    final slashIndex = result.indexOf('/');
    if (slashIndex > 0) {
      final firstSegment = result.substring(0, slashIndex);
      if (_normalizeForCompare(firstSegment) == albumNorm) {
        result = result.substring(slashIndex + 1);
      }
    }

    // Case 2: Leading "Album - Something" / "Album: Something" etc.
    final normResult = _normalizeForCompare(result);
    if (normResult.startsWith(albumNorm) &&
        normResult.length > albumNorm.length + 2) {
      final escaped = RegExp.escape(album);
      result = result.replaceFirst(
        RegExp('^$escaped[\\s:_\\-/\\\\]*', caseSensitive: false),
        '',
      );
    }

    return result.trim();
  }

  // ------------------------------------------------------------

  void _sortVideos() {
    _videos.sort((a, b) {
      final na = (a['name'] ?? '').toLowerCase();
      final nb = (b['name'] ?? '').toLowerCase();
      int resScore(String n) {
        final match = RegExp(r'(\d{3,4})p').firstMatch(n);
        if (match != null) {
          return int.tryParse(match.group(1) ?? '') ?? 0;
        }
        return 0;
      }

      final ra = resScore(na);
      final rb = resScore(nb);
      final r = rb.compareTo(ra);
      if (r != 0) return r;
      return na.compareTo(nb);
    });
  }

  void _alphabetiseVideos() {
    setState(() {
      _videos.sort((a, b) {
        final na = _prettifyFilename(a['name'] ?? '').toLowerCase();
        final nb = _prettifyFilename(b['name'] ?? '').toLowerCase();
        return na.compareTo(nb);
      });
    });
  }

  String _prettifyFilename(String name) {
    final ext = p.extension(name);
    var base = name.replaceAll(ext, '');

    // Remove album name
    base = _stripAlbumNamePrefix(base);

    // Strip leading track/episode numbers like "01 - "
    final match = RegExp(r'^(\d+)[_\s-]+(.*)').firstMatch(base);
    if (match != null) {
      base = match.group(2)!;
    }

    base = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();

    return base
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _resolutionFromName(String name) {
    final match = RegExp(r'(\d{3,4})p').firstMatch(name.toLowerCase());
    if (match != null) return '${match.group(1)}p';
    return '';
  }

  String _extLabel(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'MP4';
      case '.mkv':
        return 'MKV';
      case '.webm':
        return 'WebM';
      case '.mov':
        return 'MOV';
      case '.avi':
        return 'AVI';
      case '.m3u8':
        return 'HLS';
      default:
        return ext.isNotEmpty ? ext.replaceFirst('.', '').toUpperCase() : '';
    }
  }

  Future<void> _playSingleByIndex(int index) async {
    if (_videos.isEmpty) return;
    if (index < 0 || index >= _videos.length) index = 0;

    final entry = _videos[index];
    final name = entry['name'];
    if (name == null || name.isEmpty || !_isVideoName(name)) return;

    final url =
        'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(name)}';

    final baseThumb =
        widget.thumbUrl?.isNotEmpty == true
            ? widget.thumbUrl!
            : archiveThumbUrl(widget.identifier);

    // 🔽 Apply custom override
    final resolvedThumb = await _resolveThumb(widget.identifier, baseThumb);

    await RecentProgressService.instance.touch(
      id: widget.identifier,
      title: widget.title,
      thumb: resolvedThumb,
      kind: 'video',
      fileUrl: url,
      fileName: name,
    );

    if (!mounted) return;

    await MediaPlayerOps.playVideo(
      context,
      url: url,
      identifier: widget.identifier,
      title: widget.title,
      thumb: resolvedThumb,
      fileName: name,
    );
  }

  Future<String> _resolveThumb(String id, String currentThumb) async {
    final m = <String, String>{'identifier': id, 'thumb': currentThumb};
    await ThumbOverrideService.instance.applyToItemMaps([m]);
    return (m['thumb']?.trim().isNotEmpty == true) ? m['thumb']! : currentThumb;
  }

  @override
  Widget build(BuildContext context) {
    final thumb =
        widget.thumbUrl?.isNotEmpty == true
            ? widget.thumbUrl!
            : archiveThumbUrl(widget.identifier);

    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final coverSize = shortestSide < 600 ? 120.0 : 160.0;

    final videoCount =
        _videos.where((v) => _isVideoName(v['name'] ?? '')).length;

    final subtitleParts = <String>[
      if (videoCount > 0) '$videoCount video${videoCount == 1 ? '' : 's'}',
      if (widget.formatLabel != null && widget.formatLabel!.isNotEmpty)
        widget.formatLabel!,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          // HEADER
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: coverSize,
                    height: coverSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SwipeScrollText(
                          text: widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        if (subtitleParts.isNotEmpty)
                          Text(
                            subtitleParts.join(' • '),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play first'),
                              onPressed:
                                  _videos.isEmpty
                                      ? null
                                      : () => _playSingleByIndex(0),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.sort_by_alpha),
                              label: const Text('Sort'),
                              onPressed:
                                  _videos.isEmpty ? null : _alphabetiseVideos,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // VIDEO LIST
          Expanded(
            child: ListView.separated(
              itemCount: _videos.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final v = _videos[index];
                final name = v['name'] ?? '';
                final pretty = _prettifyFilename(name);

                return ListTile(
                  leading: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  title: _SwipeScrollText(
                    text: pretty,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () => _playSingleByIndex(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
