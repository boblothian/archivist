// lib/media/media_player_ops.dart
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/audio_player_screen.dart';
import '../screens/video_player_screen.dart';
import '../services/media_service.dart';
import '../services/recent_progress_service.dart';

class MediaPlayerOps {
  // ─────────────────────────────────────────────────────────────────────
  // VIDEO PLAYBACK
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> playVideo(
    BuildContext context, {
    String? localFilePath,
    String? url,
    required String identifier,
    required String title,
    int startPositionMs = 0,
    String? thumb,
    String? fileName,
  }) async {
    assert(
      (localFilePath != null) ^ (url != null),
      'Provide either localFilePath or url',
    );

    // Resolve local file (unchanged)
    String? localPath;
    if (localFilePath != null) {
      localPath = localFilePath;
    } else if (url != null) {
      final lower = url.toLowerCase();
      if (lower.startsWith('file://')) {
        localPath = Uri.parse(url).toFilePath();
      } else if (!url.contains('://')) {
        localPath = url;
      }
    }
    final File? file = localPath != null ? File(localPath) : null;
    final bool isLocalFile = file != null && file.existsSync();

    // Effective URL/filename (unchanged)
    final effectiveUrl = url ?? (file != null ? 'file://${file.path}' : '');
    final effectiveFileName =
        fileName ??
        (file != null
            ? file.path.split(Platform.pathSeparator).last
            : (effectiveUrl.isNotEmpty &&
                Uri.parse(effectiveUrl).pathSegments.isNotEmpty)
            ? Uri.parse(effectiveUrl).pathSegments.last
            : null);

    debugPrint('MediaPlayerOps.playVideo → local=$isLocalFile, url=$url');

    // Saved preference (per-type: 'local_internal', 'local_external', 'stream_internal', 'stream_external')
    final prefType = isLocalFile ? 'local' : 'stream';
    final savedPref = await _getSavedPreference(prefType);

    // Always possible for external (we force chooser)
    final bool canOpenExternally =
        true; // Always show button; handle failure gracefully

    // Auto-apply saved pref
    if (savedPref != null) {
      if (savedPref == 'external') {
        final opened = await _openExternally(
          context,
          file: file,
          url: url,
          isLocal: isLocalFile,
        );
        if (opened) return;
      }
      // 'internal' or invalid → proceed to dialog or internal
    }

    // Show dialog (always, unless auto-applied above)
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Play Video'),
            content: Text(
              isLocalFile
                  ? 'How would you like to play this downloaded video?'
                  : 'How would you like to play this streaming video?',
            ),
            actions: [
              if (canOpenExternally)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('external'),
                  child: const Text('Open externally'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('internal'),
                child: const Text('Play in Archivist'),
              ),
            ],
          ),
    );

    if (choice == null) return;

    await _savePreference(prefType);

    if (choice == 'external') {
      final opened = await _openExternally(
        context,
        file: file,
        url: url,
        isLocal: isLocalFile,
      );
      if (opened) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No compatible player found. Playing in Archivist.'),
        ),
      );
    }

    // Internal player fallback (unchanged)
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder:
            (_) => VideoPlayerScreen(
              file: file,
              url: url,
              identifier: identifier,
              title: title,
              startPositionMs: startPositionMs,
            ),
      ),
    );

    final pr = _extractPlaybackResult(result);
    if (pr != null) {
      await RecentProgressService.instance.updateVideo(
        id: identifier,
        title: title,
        thumb: thumb,
        fileUrl: effectiveUrl,
        fileName: effectiveFileName ?? '',
        positionMs: pr.positionMs,
        durationMs: pr.durationMs,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // AUDIO PLAYBACK
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> playAudio(
    BuildContext context, {
    String? localFilePath,
    String? url,
    required String identifier,
    required String title,
    int startPositionMs = 0,
    String? thumb,
    String? fileName,
  }) async {
    assert(
      (localFilePath != null) ^ (url != null),
      'Provide either localFilePath or url',
    );

    final effectiveUrl = url ?? 'file://${localFilePath!}';
    final effectiveFileName =
        fileName ??
        (localFilePath != null
            ? localFilePath.split(Platform.pathSeparator).last
            : Uri.parse(effectiveUrl).pathSegments.isNotEmpty
            ? Uri.parse(effectiveUrl).pathSegments.last
            : null);

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ArchiveAudioPlayerScreen(
              url: effectiveUrl,
              title: title,
              startPositionMs: startPositionMs,
            ),
      ),
    );

    final pr = _extractPlaybackResult(result);
    if (pr != null) {
      await RecentProgressService.instance.updateAudio(
        id: identifier,
        title: title,
        thumb: thumb,
        fileUrl: effectiveUrl,
        fileName: effectiveFileName ?? '',
        positionMs: pr.positionMs,
        durationMs: pr.durationMs,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // URL PICKERS
  // ─────────────────────────────────────────────────────────────────────
  static String? pickBestVideoUrl(List<String> urls) {
    if (urls.isEmpty) return null;
    final lower = urls.map((u) => u.toLowerCase()).toList();

    for (final u in lower) {
      if (u.endsWith('.mp4') || u.endsWith('.m4v'))
        return urls[lower.indexOf(u)];
    }
    for (final u in lower) {
      if (u.endsWith('.webm') || u.endsWith('.mkv'))
        return urls[lower.indexOf(u)];
    }
    for (final u in lower) {
      if (u.endsWith('.m3u8')) return urls[lower.indexOf(u)];
    }
    return urls.first;
  }

  static String? pickBestAudioUrl(List<String> urls) {
    if (urls.isEmpty) return null;
    final lower = urls.map((u) => u.toLowerCase()).toList();

    for (final u in lower) {
      if (u.endsWith('.mp3')) return urls[lower.indexOf(u)];
    }
    for (final u in lower) {
      if (u.endsWith('.ogg')) return urls[lower.indexOf(u)];
    }
    for (final u in lower) {
      if (u.endsWith('.flac')) return urls[lower.indexOf(u)];
    }
    for (final u in lower) {
      if (u.endsWith('.m3u8')) return urls[lower.indexOf(u)];
    }
    return urls.first;
  }

  // ─────────────────────────────────────────────────────────────────────
  // QUEUE VERSIONS (unchanged)
  // ─────────────────────────────────────────────────────────────────────
  static Future<void> playVideoQueue(
    BuildContext context, {
    required MediaQueue queue,
    required String identifier,
    String? title,
    int? startPositionMs,
  }) async {
    final start = queue.startIndex;
    final urls = queue.items.map((e) => e.url).toList();
    final titles = {for (final p in queue.items) p.url: p.title};

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder:
            (_) => VideoPlayerScreen(
              url: urls[start],
              queue: urls,
              queueTitles: titles,
              startIndex: start,
              identifier: identifier,
              title: title ?? queue.items[start].title,
              startPositionMs: startPositionMs,
            ),
      ),
    );

    final pr = _extractPlaybackResult(result);
    if (pr != null) {
      await RecentProgressService.instance.updateVideo(
        id: identifier,
        title: title ?? queue.items[start].title,
        fileUrl: urls[start],
        fileName: titles[urls[start]] ?? '',
        positionMs: pr.positionMs,
        durationMs: pr.durationMs,
      );
    }
  }

  static Future<void> playAudioQueue(
    BuildContext context, {
    required MediaQueue queue,
    required String identifier,
    String? title,
    int? startPositionMs,
    String? itemThumb,
  }) async {
    final start = queue.startIndex;
    final urls = queue.items.map((e) => e.url).toList();
    final titles = {for (final p in queue.items) p.url: p.title};
    final thumbs = <String, String>{for (final u in urls) u: (itemThumb ?? '')};

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ArchiveAudioPlayerScreen(
              url: urls[start],
              queue: urls,
              queueTitles: titles,
              queueThumbnails: thumbs,
              startIndex: start,
              title: title ?? queue.items[start].title,
              startPositionMs: startPositionMs,
            ),
      ),
    );

    final pr = _extractPlaybackResult(result);
    if (pr != null) {
      await RecentProgressService.instance.updateAudio(
        id: identifier,
        title: title ?? queue.items[start].title,
        fileUrl: urls[start],
        fileName: titles[urls[start]] ?? '',
        positionMs: pr.positionMs,
        durationMs: pr.durationMs,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────
  static bool isVideoUrl(String url) {
    final l = url.toLowerCase();
    return l.endsWith('.mp4') ||
        l.endsWith('.m4v') ||
        l.endsWith('.webm') ||
        l.endsWith('.mkv') ||
        l.endsWith('.m3u8') ||
        l.endsWith('.avi') ||
        l.endsWith('.mov') ||
        l.endsWith('.wmv') ||
        l.endsWith('.flv') ||
        l.endsWith('.ogv');
  }

  static bool isAudioUrl(String url) {
    final l = url.toLowerCase();
    return l.endsWith('.mp3') ||
        l.endsWith('.wav') ||
        l.endsWith('.flac') ||
        l.endsWith('.aac') ||
        l.endsWith('.ogg') ||
        l.endsWith('.m4a') ||
        l.endsWith('.opus');
  }

  // ─────────────────────────────────────────────────────────────────────
  // EXTERNAL OPEN (local file OR remote URL)
  // ─────────────────────────────────────────────────────────────────────
  static Future<bool> _openExternally(
    BuildContext context, {
    File? file,
    String? url,
    required bool isLocal,
  }) async {
    if (!Platform.isAndroid) {
      // iOS: fall back to open_filex or url_launcher
      if (isLocal && file != null) {
        return await _openLocalFile(file.path, context);
      } else if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        }
      }
      return false;
    }

    // ──────────────────────────────────────────────────────────────
    // ANDROID: FORCE CHOOSER DIALOG (like in your screenshot)
    // ──────────────────────────────────────────────────────────────
    try {
      final AndroidIntent intent = AndroidIntent(
        action: 'action_view',
        // Use correct MIME type
        type: isLocal ? 'video/*' : 'video/*',
        data: isLocal && file != null ? Uri.file(file.path).toString() : url,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        // CRITICAL: package: null → forces chooser
        package: null,
      );

      // This will show the exact chooser from your screenshot
      await intent.launchChooser('Choose Player');
      return true;
    } catch (e) {
      debugPrint('Intent chooser failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open chooser. Trying fallback...'),
        ),
      );

      // Fallback: try open_filex (local) or url_launcher (remote)
      if (isLocal && file != null) {
        return await _openLocalFile(file.path, context);
      } else if (url != null) {
        try {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return true;
          }
        } catch (_) {}
      }
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // LOCAL FILE OPENER (iOS + Android fallback)
  // ─────────────────────────────────────────────────────────────────────
  static Future<bool> _openLocalFile(
    String filePath,
    BuildContext context,
  ) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type == ResultType.done) {
        return true;
      } else {
        String message;
        switch (result.type) {
          case ResultType.noAppToOpen:
            message = 'No app found to open this file.';
            break;
          case ResultType.fileNotFound:
            message = 'File not found.';
            break;
          case ResultType.permissionDenied:
            message = 'Permission denied.';
            break;
          case ResultType.error:
          default:
            message = 'Error opening file: ${result.message}';
            break;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return false;
      }
    } catch (e) {
      debugPrint('Failed to open local file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open file externally.')),
      );
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // PREFERENCE HELPERS
  // ─────────────────────────────────────────────────────────────────────
  static const String _prefKey =
      'video_playback_preference'; // 'internal' | 'external'

  static Future<String?> _getSavedPreference(String prefType) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  static Future<void> _savePreference(String choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, choice);
  }
}

// ─────────────────────────────────────────────────────────────────────
// RESULT MODEL
// ─────────────────────────────────────────────────────────────────────
class PlaybackResult {
  final int positionMs;
  final int durationMs;
  const PlaybackResult({required this.positionMs, required this.durationMs});
}

PlaybackResult? _extractPlaybackResult(dynamic result) {
  if (result == null) return null;
  if (result is PlaybackResult) return result;

  if (result is Map) {
    final pos = result['positionMs'];
    final dur = result['durationMs'];
    if (pos is int && dur is int) {
      return PlaybackResult(positionMs: pos, durationMs: dur);
    }
    if (pos is int) {
      return PlaybackResult(positionMs: pos, durationMs: dur is int ? dur : 0);
    }
  }

  if (result is int) {
    return PlaybackResult(positionMs: result, durationMs: 0);
  }
  return null;
}
