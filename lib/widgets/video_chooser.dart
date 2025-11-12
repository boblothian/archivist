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
                title: Text(
                  pretty.isEmpty ? op.name : pretty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '$fmtLabel  •  $res  •  $size',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  final mime = _guessMime(op.name, op.format);
                  final choice = await showDialog<String>(
                    context: context,
                    builder:
                        (dCtx) => AlertDialog(
                          title: const Text('Open video'),
                          content: const Text(
                            'Choose how you’d like to open this video.',
                          ),
                          actions: [
                            TextButton(
                              onPressed:
                                  () => Navigator.of(dCtx).pop('internal'),
                              child: const Text('In app'),
                            ),
                            TextButton(
                              onPressed:
                                  () => Navigator.of(dCtx).pop('external'),
                              child: const Text('External app'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(dCtx).pop('cancel'),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                  );

                  if (choice == 'cancel' || choice == null) return;

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

                  FocusScope.of(context).unfocus();
                  if (choice == 'external') {
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  } else {
                    await MediaPlayerOps.playVideo(
                      context,
                      url: url,
                      identifier: identifier,
                      title: title,
                    );
                  }

                  if (Navigator.canPop(sheetCtx)) Navigator.pop(sheetCtx);
                },
              );
            },
          ),
        ),
      );
    },
  );
}
