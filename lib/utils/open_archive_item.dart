import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';

import 'archive_helpers.dart';

/// Opens a bottom-sheet that lets the user:
///  • pick a video file from the list
///  • choose “Browser” or “Installed app”
///  • updates recent progress
///
/// Returns `Future<void>` – the dialog handles navigation itself.
Future<void> showVideoFileChooser({
  required BuildContext context,
  required String identifier,
  required String title,
  required List<Map<String, String>> videoOptions,
  String Function(String)? thumbForId,
  String? thumb,
}) async {
  // -----------------------------------------------------------------
  // Helper: choose the best thumbnail (Archive Item screen thumb wins)
  // -----------------------------------------------------------------
  final String thumbUrl =
      (() {
        final t = thumb?.trim();
        if (t != null && t.isNotEmpty) return t; // 1) explicit thumb
        if (thumbForId != null) {
          return thumbForId(identifier); // 2) provided resolver
        }
        return archiveThumbUrl(identifier); // 3) default IA services/img
      })();

  // -----------------------------------------------------------------
  // Show the bottom sheet
  // -----------------------------------------------------------------
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder:
        (ctx) => _VideoChooserSheet(
          identifier: identifier,
          title: title,
          options: videoOptions,
          thumbUrl: thumbUrl,
        ),
  );
}

// ---------------------------------------------------------------------
// Private widget – the actual sheet UI
// ---------------------------------------------------------------------
class _VideoChooserSheet extends StatelessWidget {
  final String identifier;
  final String title;
  final List<Map<String, String>> options;
  final String thumbUrl;

  const _VideoChooserSheet({
    required this.identifier,
    required this.title,
    required this.options,
    required this.thumbUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Choose a file and how to open it'),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final op = options[i];
                final fmtLower = (op['fmt'] ?? '').toLowerCase();
                final icon =
                    (fmtLower.contains('mp4') || fmtLower.contains('h.264'))
                        ? Icons.movie
                        : Icons.video_file;

                return ListTile(
                  leading: Icon(icon),
                  title: Text(
                    op['pretty'] ?? op['name'] ?? 'Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${(op['fmt'] ?? '').toUpperCase()}  •  ${op['res'] ?? ''}  •  ${op['size'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _handleTap(context, op),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Core logic – unified URL + recent-progress with correct thumb
  // ---------------------------------------------------------------
  Future<void> _handleTap(BuildContext ctx, Map<String, String> op) async {
    final name = op['name'] ?? '';
    if (name.isEmpty) return;

    // Prefer the provided URL; if missing, build from identifier + name.
    final urlStr =
        op['url'] ??
        'https://archive.org/download/$identifier/${Uri.encodeComponent(name)}';
    final uri = Uri.parse(urlStr);

    // ---- tiny toast with the selected file ----
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            '${op['pretty'] ?? name} • ${(op['fmt'] ?? '').toUpperCase()} • ${op['size'] ?? ''}',
          ),
        ),
      );
    }

    // close the bottom-sheet
    if (ctx.mounted) Navigator.pop(ctx);

    // ---- update recent progress (uses the chosen thumb) ----
    await RecentProgressService.instance.updateVideo(
      id: identifier,
      title: title,
      thumb: thumbUrl,
      percent: 0.0,
      fileUrl: urlStr,
      fileName: name,
    );

    // ---- decide mime type ----
    String mime = 'video/*';
    final fmt = (op['fmt'] ?? '').toString().toLowerCase();
    final nameLower = name.toLowerCase();

    if (fmt.contains('webm') || nameLower.endsWith('.webm')) {
      mime = 'video/webm';
    } else if (fmt.contains('mp4') ||
        fmt.contains('h.264') ||
        nameLower.endsWith('.mp4') ||
        nameLower.endsWith('.m4v')) {
      mime = 'video/mp4';
    } else if (fmt.contains('matroska') || nameLower.endsWith('.mkv')) {
      mime = 'video/x-matroska';
    } else if (nameLower.endsWith('.m3u8')) {
      mime = 'application/vnd.apple.mpegurl';
    }
  }
}
