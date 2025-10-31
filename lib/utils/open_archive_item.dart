// lib/utils/video_file_chooser.dart

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String Function(String)?
  thumbForId, // optional – defaults to archive.org service
}) async {
  // -----------------------------------------------------------------
  // Helper: default thumb URL (used for recent-progress)
  // -----------------------------------------------------------------
  String _defaultThumb(String id) => 'https://archive.org/services/img/$id';
  final thumbUrl = (thumbForId ?? _defaultThumb)(identifier);

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
                final icon =
                    (op['fmt'] ?? '').toLowerCase().contains('mp4') ||
                            (op['fmt'] ?? '').toLowerCase().contains('h.264')
                        ? Icons.movie
                        : Icons.video_file;

                return ListTile(
                  leading: Icon(icon),
                  title: Text(
                    op['pretty']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${(op['fmt'] ?? '').toUpperCase()}  •  ${op['res']}  •  ${op['size']}',
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
  // Core logic – same as the original block
  // ---------------------------------------------------------------
  Future<void> _handleTap(BuildContext ctx, Map<String, String> op) async {
    final uri = Uri.parse(op['url']!);
    final name = op['name']!;
    final videoUrl =
        'https://archive.org/download/$identifier/${Uri.encodeComponent(name)}';

    // ---- show a tiny toast with the selected file ----
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            '${op['pretty']} • ${(op['fmt'] ?? '').toUpperCase()} • ${op['size']}',
          ),
        ),
      );
    }

    // ---- ask user: Browser or App? ----
    final choice = await showDialog<String>(
      context: ctx,
      builder:
          (dCtx) => AlertDialog(
            title: const Text('Open video'),
            content: const Text(
              'Choose how you’d like to open or save this video:',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, 'browser'),
                child: const Text('Browser'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dCtx, 'app'),
                child: const Text('Installed app'),
              ),
            ],
          ),
    );

    if (choice == null) return; // user cancelled

    // close the bottom-sheet
    if (ctx.mounted) Navigator.pop(ctx);

    // ---- update recent progress (same as original) ----
    await RecentProgressService.instance.updateVideo(
      id: identifier,
      title: title,
      thumb: thumbUrl,
      percent: 0.0,
      fileUrl: videoUrl,
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

    // ---- launch ----
    if (choice == 'browser') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await openExternallyWithChooser(
        url: uri.toString(),
        mimeType: mime,
        chooserTitle: 'Open with',
      );
    }
  }
}

// -----------------------------------------------------------------
// Helper that lives in your project (already exists)
// -----------------------------------------------------------------
Future<void> openExternallyWithChooser({
  required String url,
  required String mimeType,
  required String chooserTitle,
}) async {
  // You already have this somewhere (android_intent_plus, url_launcher, …)
  // Keep the exact implementation you used before.
  // Example using android_intent_plus:
  // final intent = AndroidIntent(
  //   action: 'action_view',
  //   data: url,
  //   type: mimeType,
  //   flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
  // );
  // await intent.launchChooser(chooserTitle);
}
