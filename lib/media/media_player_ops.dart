// lib/media/media_player_ops.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/audio_player_screen.dart';
import '../screens/video_player_screen.dart';
import '../services/media_service.dart';
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

    // Single-item playback: do NOT pass queue args.
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

  /// Play audio from a local file or URL.
  static Future<void> playAudio(
    BuildContext context, {
    String? localFilePath,
    String? url,
    required String identifier,
    required String title,

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

  /// Choose a sensible video URL from a list.
  static String? pickBestVideoUrl(List<String> urls) {
    if (urls.isEmpty) return null;
    final lower = urls.map((u) => u.toLowerCase()).toList();

    for (int i = 0; i < urls.length; i++) {
      final u = lower[i];
      if (u.endsWith('.mp4') || u.endsWith('.m4v')) return urls[i];
    }
    for (int i = 0; i < urls.length; i++) {
      final u = lower[i];
      if (u.endsWith('.webm') || u.endsWith('.mkv')) return urls[i];
    }
    for (int i = 0; i < urls.length; i++) {
      if (lower[i].endsWith('.m3u8')) return urls[i];
    }
    return urls.first;
  }

  // -------------------- QUEUE VERSIONS --------------------

  static Future<void> playVideoQueue(
    BuildContext context, {
    required MediaQueue queue,
    required String identifier, // ← make this required & non-nullable
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
    required String identifier, // ← make this required & non-nullable
    String? title,
    int? startPositionMs,
    String? itemThumb, // optional: single image for all tracks
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

  /// Choose a sensible audio URL from a list.
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

  // ─────────────────────────────────────────────────────────────────────
  // Helpers
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
}

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
