// lib/media/media_player_ops.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/audio_player_screen.dart';
import '../screens/video_player_screen.dart';
import '../services/recent_progress_service.dart';

class MediaPlayerOps {
  /// Play video either from a local file path OR a URL.
  /// - Exactly one of [localFilePath] or [url] should be provided.
  /// - Optional [startPositionMs] lets the player seek to a resume point.
  /// - If the player screen returns a position/duration on pop, we persist it.
  static Future<void> playVideo(
    BuildContext context, {
    String? localFilePath,
    String? url,
    required String identifier,
    required String title,

    // NEW: resume support
    int startPositionMs = 0,

    // Optional extras (used when saving progress)
    String? thumb,
    String? fileName,
  }) async {
    assert(
      (localFilePath != null) ^ (url != null),
      'Provide either localFilePath or url',
    );

    final file = (localFilePath != null) ? File(localFilePath) : null;
    final effectiveUrl = url ?? 'file://${file!.path}';
    final effectiveFileName =
        fileName ??
        (localFilePath != null
            ? localFilePath.split(Platform.pathSeparator).last
            : Uri.parse(effectiveUrl).pathSegments.isNotEmpty
            ? Uri.parse(effectiveUrl).pathSegments.last
            : null);

    // Push player screen. We pass startPositionMs ONLY IF the screen supports it.
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder:
            (_) => VideoPlayerScreen(
              file: file,
              url: url,
              identifier: identifier,
              title: title,
              // If your VideoPlayerScreen doesn't have this param, remove it here
              // or add `final int? startPositionMs;` to that screen.
              startPositionMs: startPositionMs,
            ),
      ),
    );

    // Try to capture playback progress and persist it.
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
        // percent is computed from position/duration inside updateVideo
      );
    }
  }

  /// Play audio from a local file or URL.
  /// - Exactly one of [localFilePath] or [url] should be provided.
  /// - Optional [startPositionMs] lets the player seek to a resume point.
  /// - If the player screen returns a position/duration on pop, we persist it.
  static Future<void> playAudio(
    BuildContext context, {
    String? localFilePath,
    String? url,
    required String identifier,
    required String title,

    // NEW: resume support
    int startPositionMs = 0,

    // Optional extras (used when saving progress)
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

    // Push audio player. Pass startPositionMs only if your screen supports it.
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ArchiveAudioPlayerScreen(
              url: effectiveUrl,
              title: title,
              // Add this optional named parameter to your audio screen if not present.
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

  /// Choose a sensible video URL from a list:
  /// - prefer MP4 for broader cast support
  /// - fallback to HLS (.m3u8)
  static String? pickBestVideoUrl(List<String> urls) {
    if (urls.isEmpty) return null;
    final lower = urls.map((u) => u.toLowerCase()).toList();
    // prefer mp4/m4v
    for (int i = 0; i < urls.length; i++) {
      final u = lower[i];
      if (u.endsWith('.mp4') || u.endsWith('.m4v')) return urls[i];
    }
    // then webm/mkv
    for (int i = 0; i < urls.length; i++) {
      final u = lower[i];
      if (u.endsWith('.webm') || u.endsWith('.mkv')) return urls[i];
    }
    // then HLS
    for (int i = 0; i < urls.length; i++) {
      if (lower[i].endsWith('.m3u8')) return urls[i];
    }
    // otherwise first
    return urls.first;
  }

  /// Choose a sensible audio URL from a list:
  /// - prefer mp3, then ogg, then flac, then m3u8 streams
  static String? pickBestAudioUrl(List<String> urls) {
    if (urls.isEmpty) return null;
    final lower = urls.map((u) => u.toLowerCase()).toList();
    for (int i = 0; i < urls.length; i++) {
      if (lower[i].endsWith('.mp3')) return urls[i];
    }
    for (int i = 0; i < urls.length; i++) {
      if (lower[i].endsWith('.ogg')) return urls[i];
    }
    for (int i = 0; i < urls.length; i++) {
      if (lower[i].endsWith('.flac')) return urls[i];
    }
    for (int i = 0; i < urls.length; i++) {
      if (lower[i].endsWith('.m3u8')) return urls[i];
    }
    return urls.first;
  }
}

/// Flexible return type from player screens.
/// You can:
/// - `Navigator.pop(context, PlaybackResult(positionMs: ..., durationMs: ...))`
/// - `Navigator.pop(context, {'positionMs': 1234, 'durationMs': 9999})`
/// - `Navigator.pop(context, 1234)`  // position only
class PlaybackResult {
  final int positionMs;
  final int durationMs;
  const PlaybackResult({required this.positionMs, required this.durationMs});
}

PlaybackResult? _extractPlaybackResult(dynamic result) {
  if (result == null) return null;

  // Already a typed result
  if (result is PlaybackResult) return result;

  // Map-style: {'positionMs': int, 'durationMs': int}
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

  // Plain int: treat as position only
  if (result is int) {
    return PlaybackResult(positionMs: result, durationMs: 0);
  }

  return null;
}
