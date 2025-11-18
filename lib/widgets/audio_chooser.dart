// lib/widgets/audio_chooser.dart
import 'package:flutter/material.dart';

class ArchiveAudioMeta {
  final String name;
  final String format;
  final int? sizeBytes;
  final int? bitrateKbps;

  const ArchiveAudioMeta({
    required this.name,
    required this.format,
    this.sizeBytes,
    this.bitrateKbps,
  });

  factory ArchiveAudioMeta.fromMap(Map<String, dynamic> m) {
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

    int? parseBitrate(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;

      final direct = int.tryParse(s);
      if (direct != null) return direct;

      final match = RegExp(r'(\d+)').firstMatch(s);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
      return null;
    }

    return ArchiveAudioMeta(
      name: (m['name'] ?? '').toString(),
      format: (m['format'] ?? m['fmt'] ?? '').toString(),
      sizeBytes: parseSize(m['size']),
      bitrateKbps: parseBitrate(m['bitrate']),
    );
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

String _extFromName(String name) {
  final m = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(name);
  return (m?.group(1) ?? '').toLowerCase();
}

bool _isAudioName(String name) {
  final ext = _extFromName(name);
  return ['mp3', 'ogg', 'flac', 'm4a', 'wav', 'opus', 'aac'].contains(ext);
}

String _formatLabel(String ext) {
  switch (ext) {
    case 'mp3':
      return 'MP3';
    case 'ogg':
      return 'Ogg Vorbis';
    case 'flac':
      return 'FLAC';
    case 'm4a':
      return 'M4A / AAC';
    case 'wav':
      return 'WAV';
    case 'opus':
      return 'Opus';
    case 'aac':
      return 'AAC';
    default:
      return ext.toUpperCase();
  }
}

class _AudioFormatOption {
  final String ext; // e.g. "mp3"
  final int trackCount;
  final int? totalSizeBytes;
  final int? typicalBitrateKbps;

  _AudioFormatOption({
    required this.ext,
    required this.trackCount,
    this.totalSizeBytes,
    this.typicalBitrateKbps,
  });
}

/// Lets the user pick an audio format for this identifier.
/// Returns the chosen extension (e.g. ".mp3") or null if cancelled.
Future<String?> showAudioFormatChooser(
  BuildContext context, {
  required String identifier,
  required String title,
  required List<dynamic> files,
}) async {
  // Build meta list from raw metadata
  final metas =
      files
          .map(
            (f) =>
                f is ArchiveAudioMeta
                    ? f
                    : ArchiveAudioMeta.fromMap(f as Map<String, dynamic>),
          )
          .where((m) => m.name.isNotEmpty && _isAudioName(m.name))
          .toList();

  if (metas.isEmpty) {
    // No audio, nothing to choose
    return null;
  }

  // Group by extension
  final Map<String, List<ArchiveAudioMeta>> byExt = {};
  for (final m in metas) {
    final ext = _extFromName(m.name);
    byExt.putIfAbsent(ext, () => []).add(m);
  }

  final options = <_AudioFormatOption>[];

  byExt.forEach((ext, list) {
    final count = list.length;
    final totalSize = list.fold<int?>(
      0,
      (prev, e) =>
          e.sizeBytes == null ? prev : (prev ?? 0) + (e.sizeBytes ?? 0),
    );
    // Just grab the first non-null bitrate as "typical"
    final typicalBitrate =
        list
            .firstWhere((e) => e.bitrateKbps != null, orElse: () => list.first)
            .bitrateKbps;

    options.add(
      _AudioFormatOption(
        ext: ext,
        trackCount: count,
        totalSizeBytes: totalSize == 0 ? null : totalSize,
        typicalBitrateKbps: typicalBitrate,
      ),
    );
  });

  // Sort: higher bitrate first, then larger size, then ext name
  options.sort((a, b) {
    final bitA = a.typicalBitrateKbps ?? 0;
    final bitB = b.typicalBitrateKbps ?? 0;
    final r = bitB.compareTo(bitA);
    if (r != 0) return r;
    final sizeA = a.totalSizeBytes ?? 0;
    final sizeB = b.totalSizeBytes ?? 0;
    final r2 = sizeB.compareTo(sizeA);
    if (r2 != 0) return r2;
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Choose audio format',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final op = options[i];
                  final label = _formatLabel(op.ext);
                  final size = _humanBytes(op.totalSizeBytes);
                  final br =
                      op.typicalBitrateKbps != null
                          ? '${op.typicalBitrateKbps} kbps'
                          : null;

                  final subtitleParts = <String>[
                    '${op.trackCount} track${op.trackCount == 1 ? '' : 's'}',
                    if (br != null) br,
                    if (op.totalSizeBytes != null) size,
                  ];

                  return ListTile(
                    leading: const Icon(Icons.audiotrack),
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
