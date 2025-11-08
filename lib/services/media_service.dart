// lib/services/media_service.dart
import 'dart:convert';

import 'package:dio/dio.dart';

class ArchiveMediaInfo {
  final String identifier;
  final String? title;
  final String? license;
  final String? rights;
  final List<String> videoUrls; // mp4/m3u8
  final List<String> audioUrls; // mp3/ogg
  final Map<String, String> displayNames; // url -> "480p MP4", etc.

  ArchiveMediaInfo({
    required this.identifier,
    required this.title,
    required this.license,
    required this.rights,
    required this.videoUrls,
    required this.audioUrls,
    required this.displayNames,
  });
}

class MediaService {
  final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 15)),
  );

  Future<ArchiveMediaInfo> fetchInfo(String identifier) async {
    // Archive item metadata JSON
    final url = 'https://archive.org/metadata/$identifier';
    final resp = await _dio.get(url);
    final data = resp.data is String ? json.decode(resp.data) : resp.data;

    final meta = data['metadata'] ?? {};
    final files = (data['files'] as List?) ?? [];

    final title = (meta['title'] as String?)?.trim();
    final license = (meta['license'] as String?)?.trim();
    final rights = (meta['rights'] as String?)?.trim();

    final List<String> videoUrls = [];
    final List<String> audioUrls = [];
    final Map<String, String> labels = {};

    // Prefer direct MP4/WEBM/M3U8 and MP3/OGG
    for (final f in files) {
      final name = (f['name'] as String?) ?? '';
      if (name.isEmpty) continue;
      final lower = name.toLowerCase();

      final fileUrl = 'https://archive.org/download/$identifier/$name';

      if (lower.endsWith('.mp4') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.m3u8')) {
        videoUrls.add(fileUrl);
        labels[fileUrl] = _prettyLabel(name);
      } else if (lower.endsWith('.mp3') ||
          lower.endsWith('.ogg') ||
          lower.endsWith('.flac') ||
          lower.endsWith('.m3u8')) {
        audioUrls.add(fileUrl);
        labels[fileUrl] = _prettyLabel(name);
      }
    }

    // Fallback: some items only expose <identifier>.mp4/<identifier>.mp3
    if (videoUrls.isEmpty) {
      final fallbackMp4 =
          'https://archive.org/download/$identifier/$identifier.mp4';
      videoUrls.add(fallbackMp4);
      labels[fallbackMp4] = 'Video (fallback MP4)';
    }
    if (audioUrls.isEmpty) {
      final fallbackMp3 =
          'https://archive.org/download/$identifier/$identifier.mp3';
      audioUrls.add(fallbackMp3);
      labels[fallbackMp3] = 'Audio (fallback MP3)';
    }

    return ArchiveMediaInfo(
      identifier: identifier,
      title: title,
      license: license,
      rights: rights,
      videoUrls: videoUrls,
      audioUrls: audioUrls,
      displayNames: labels,
    );
  }

  bool isDownloadAllowed(ArchiveMediaInfo info) {
    final l = (info.license ?? info.rights ?? '').toLowerCase();
    if (l.isEmpty) return false;
    // Heuristics that safely allow PD/CC
    return l.contains('public domain') ||
        l.contains('cc-by') ||
        l.contains('cc by') ||
        l.contains('creative commons') ||
        l.contains('cc0') ||
        l.contains('cc-by-sa') ||
        l.contains('cc-sa') ||
        l.contains(
          'cc-nc',
        ) || // NC still allows downloading with attribution (non-commercial)
        l.contains('cc-'); // generic CC catch
  }

  String _prettyLabel(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('360')) return '360p';
    if (lower.contains('480')) return '480p';
    if (lower.contains('720')) return '720p';
    if (lower.contains('1080')) return '1080p';
    if (lower.endsWith('.m3u8')) return 'HLS stream';
    if (lower.endsWith('.mp3')) return 'MP3';
    if (lower.endsWith('.ogg')) return 'OGG';
    return filename;
  }
}
