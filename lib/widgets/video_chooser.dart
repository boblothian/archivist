// lib/widgets/video_chooser.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../media/media_player_ops.dart';
import '../screens/video_album_screen.dart';
import '../services/recent_progress_service.dart';
import '../utils/archive_helpers.dart';

class ArchiveVideoMeta {
  final String name;
  final String format;
  final int? sizeBytes;
  final int? width;
  final int? height;

  const ArchiveVideoMeta({
    required this.name,
    required this.format,
    this.sizeBytes,
    this.width,
    this.height,
  });

  factory ArchiveVideoMeta.fromMap(Map<String, dynamic> m) {
    int? parseSize(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;

      final direct = int.tryParse(s);
      if (direct != null) return direct;

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

    int? parseDim(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return int.tryParse(s);
    }

    return ArchiveVideoMeta(
      name: (m['name'] ?? '').toString(),
      format: (m['format'] ?? m['fmt'] ?? '').toString(),
      sizeBytes: parseSize(m['size']),
      width: parseDim(m['width']),
      height: parseDim(m['height']),
    );
  }
}

// ─────────────────────────────────────
// Helpers
// ─────────────────────────────────────

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

String _extFromName(String name) {
  final m = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(name);
  return (m?.group(1) ?? '').toLowerCase();
}

bool _isVideoName(String name) {
  final ext = _extFromName(name);
  return [
    'mp4',
    'm4v',
    'mkv',
    'webm',
    'mov',
    'avi',
    'm3u8', // HLS playlist
  ].contains(ext);
}

String _videoFormatLabel(String ext) {
  switch (ext) {
    case 'mp4':
    case 'm4v':
      return 'MP4 / H.264';
    case 'mkv':
      return 'MKV / Matroska';
    case 'webm':
      return 'WebM';
    case 'mov':
      return 'QuickTime MOV';
    case 'avi':
      return 'AVI';
    case 'm3u8':
      return 'HLS playlist (.m3u8)';
    default:
      return ext.toUpperCase();
  }
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

String _resolutionLabel(ArchiveVideoMeta m) {
  if (m.width != null && m.height != null) {
    return '${m.width}×${m.height}';
  }
  // Try to infer from filename like "1080p", "720p"
  final match = RegExp(r'(\d{3,4})p').firstMatch(m.name.toLowerCase());
  if (match != null) {
    return '${match.group(1)}p';
  }
  return 'Unknown resolution';
}

// ─────────────────────────────────────
// Shared playback helper
// ─────────────────────────────────────

Future<void> _playVideoMeta(
  BuildContext context, {
  required String identifier,
  required String title,
  required ArchiveVideoMeta meta,
}) async {
  final ext = _extFromName(meta.name);
  final rawFmt = meta.format.trim().toLowerCase();
  final remoteUrl =
      'https://archive.org/download/$identifier/${Uri.encodeComponent(meta.name)}';

  final isMkv =
      ext == 'mkv' || rawFmt.contains('matroska') || rawFmt.contains('mkv');

  try {
    await RecentProgressService.instance.touch(
      id: identifier,
      title: title,
      thumb: archiveThumbUrl(identifier),
      kind: 'video',
      fileUrl: remoteUrl,
      fileName: meta.name,
    );
  } catch (_) {}

  await MediaPlayerOps.playVideo(
    context,
    url: remoteUrl,
    identifier: identifier,
    title: title,
    thumb: archiveThumbUrl(identifier),
    fileName: meta.name,
  );
}

// ─────────────────────────────────────
// Format grouping (audio_chooser-style)
// ─────────────────────────────────────

class _VideoFormatOption {
  final String ext; // e.g. "mp4"
  final int fileCount;
  final int? totalSizeBytes;
  final String? typicalResolution;

  _VideoFormatOption({
    required this.ext,
    required this.fileCount,
    this.totalSizeBytes,
    this.typicalResolution,
  });
}

Future<String?> _showVideoFormatSheet(
  BuildContext context, {
  required String identifier,
  required String title,
  required List<ArchiveVideoMeta> metas,
}) async {
  // Group by extension
  final Map<String, List<ArchiveVideoMeta>> byExt = {};
  for (final m in metas) {
    final ext = _extFromName(m.name);
    if (ext.isEmpty) continue;
    byExt.putIfAbsent(ext, () => []).add(m);
  }

  if (byExt.isEmpty) return null;

  final options = <_VideoFormatOption>[];

  byExt.forEach((ext, list) {
    final count = list.length;
    final totalSize = list.fold<int?>(
      0,
      (prev, e) =>
          e.sizeBytes == null ? prev : (prev ?? 0) + (e.sizeBytes ?? 0),
    );

    final firstWithRes = list.firstWhere(
      (e) => e.width != null && e.height != null,
      orElse: () => list.first,
    );
    final typicalRes = _resolutionLabel(firstWithRes);

    options.add(
      _VideoFormatOption(
        ext: ext,
        fileCount: count,
        totalSizeBytes: totalSize == 0 ? null : totalSize,
        typicalResolution: typicalRes,
      ),
    );
  });

  // Sort: larger total size first (usually higher quality), then ext name
  options.sort((a, b) {
    final sizeA = a.totalSizeBytes ?? 0;
    final sizeB = b.totalSizeBytes ?? 0;
    final r = sizeB.compareTo(sizeA);
    if (r != 0) return r;
    return a.ext.compareTo(b.ext);
  });

  return showModalBottomSheet<String?>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose video format',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final op = options[i];
                  final label = _videoFormatLabel(op.ext);
                  final size = _humanBytes(op.totalSizeBytes);
                  final res = op.typicalResolution;

                  final subtitleParts = <String>[
                    '${op.fileCount} file${op.fileCount == 1 ? '' : 's'}',
                    if (res != null && res != 'Unknown resolution') res,
                    if (op.totalSizeBytes != null) size,
                  ];

                  return ListTile(
                    leading: const Icon(Icons.movie),
                    title: Text(label),
                    subtitle: Text(subtitleParts.join(' • ')),
                    onTap: () {
                      Navigator.pop(sheetCtx, '.${op.ext}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ─────────────────────────────────────
// PUBLIC API: showVideoChooser
// (called from CollectionDetailScreen & Favourites)
// ─────────────────────────────────────

/// High-level helper that mirrors the audio flow:
/// - If only 1 video total → play it.
/// - Otherwise ask for format (mp4/mkv/etc).
///   - If only 1 file of that type → play it.
///   - If >1 → push VideoAlbumScreen for that type.
///
/// Callers just `await showVideoChooser(...)` and don't need to care.
Future<void> showVideoChooser(
  BuildContext context, {
  required String identifier,
  required String title,
  required List<dynamic> files,
}) async {
  // Normalise into ArchiveVideoMeta & keep only video-ish names
  final metas =
      files
          .map(
            (f) =>
                f is ArchiveVideoMeta
                    ? f
                    : ArchiveVideoMeta.fromMap(f as Map<String, dynamic>),
          )
          .where((m) => m.name.isNotEmpty && _isVideoName(m.name))
          .toList();

  if (metas.isEmpty) {
    // Fallback: open on web
    await launchUrl(
      Uri.parse('https://archive.org/details/$identifier'),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  // Only 1 video total → just play it.
  if (metas.length == 1) {
    await _playVideoMeta(
      context,
      identifier: identifier,
      title: title,
      meta: metas.first,
    );
    return;
  }

  // Ask user which format they want
  final chosenExt = await _showVideoFormatSheet(
    context,
    identifier: identifier,
    title: title,
    metas: metas,
  );

  if (chosenExt == null) {
    // User cancelled
    return;
  }

  final filtered =
      metas
          .where((m) => m.name.toLowerCase().endsWith(chosenExt.toLowerCase()))
          .toList();

  final effective = filtered.isNotEmpty ? filtered : metas;

  if (effective.length == 1) {
    await _playVideoMeta(
      context,
      identifier: identifier,
      title: title,
      meta: effective.first,
    );
  } else {
    final fmtLabel = chosenExt.replaceFirst('.', '').toUpperCase();

    // Map ArchiveVideoMeta → Map<String, String> for VideoAlbumScreen
    final fileMaps =
        effective.map<Map<String, String>>((m) => {'name': m.name}).toList();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => VideoAlbumScreen(
              identifier: identifier,
              title: title,
              files: fileMaps,
              thumbUrl: archiveThumbUrl(identifier),
              formatLabel: fmtLabel,
            ),
      ),
    );
  }
}
