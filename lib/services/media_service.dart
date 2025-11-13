// lib/services/media_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

enum MediaType { audio, video }

class Playable {
  final String url;
  final String title;
  const Playable({required this.url, required this.title});
}

class MediaQueue {
  final List<Playable> items;
  final MediaType type;
  final int startIndex;
  const MediaQueue({
    required this.items,
    required this.type,
    this.startIndex = 0,
  });
}

class ArchiveMediaInfo {
  final String identifier;
  final List<String> audioUrls;
  final List<String> videoUrls;
  final Map<String, String> displayNames;
  final String? license;
  final String? rights;

  ArchiveMediaInfo({
    required this.identifier,
    required this.audioUrls,
    required this.videoUrls,
    required this.displayNames,
    this.license,
    this.rights,
  });

  factory ArchiveMediaInfo.fromJson(String id, Map<String, dynamic> json) {
    final files = json['files'] as List? ?? [];
    final audio = <String>[];
    final video = <String>[];
    final names = <String, String>{};

    for (final f in files) {
      final name = f['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final lower = name.toLowerCase();
      final url = 'https://archive.org/download/$id/$name';
      names[url] = name;
      if (lower.endsWith('.mp3') ||
          lower.endsWith('.ogg') ||
          lower.endsWith('.flac') ||
          lower.endsWith('.m4a')) {
        audio.add(url);
      } else if (lower.endsWith('.mp4') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.m3u8')) {
        video.add(url);
      }
    }

    return ArchiveMediaInfo(
      identifier: id,
      audioUrls: audio,
      videoUrls: video,
      displayNames: names,
      license: json['metadata']?['licenseurl'] ?? '',
      rights: json['metadata']?['rights'] ?? '',
    );
  }

  String get thumbnailUrl => 'https://archive.org/services/img/$identifier';
}

// Internal cache entry for both media types
class _ItemQueues {
  final List<Playable> audio;
  final List<Playable> video;
  const _ItemQueues({required this.audio, required this.video});
  List<Playable> byType(MediaType t) => t == MediaType.audio ? audio : video;
}

class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  final Map<String, _ItemQueues> _queues = {};

  /// Fetch archive.org item info
  Future<ArchiveMediaInfo> fetchInfo(String identifier) async {
    final res = await http.get(
      Uri.parse('https://archive.org/metadata/$identifier'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load metadata');
    }
    final jsonData = json.decode(res.body) as Map<String, dynamic>;
    final info = ArchiveMediaInfo.fromJson(identifier, jsonData);
    primeQueues(info);
    return info;
  }

  // ---------- QUEUE LOGIC ----------

  /// Cache the queue lists for a given item.
  void primeQueues(ArchiveMediaInfo info) {
    _queues[info.identifier] = _ItemQueues(
      audio: _buildPlayableList(info, MediaType.audio),
      video: _buildPlayableList(info, MediaType.video),
    );
  }

  /// Build a MediaQueue for this item and media type.
  MediaQueue buildQueueForInfo(
    ArchiveMediaInfo info, {
    required MediaType type,
    String? startUrl,
  }) {
    final items = _buildPlayableList(info, type);
    final idx = _startIndex(items, startUrl);
    return MediaQueue(items: items, type: type, startIndex: idx);
  }

  /// Return a cached queue if available.
  MediaQueue? getQueue(String identifier, MediaType type, {String? startUrl}) {
    final cached = _queues[identifier];
    if (cached == null) return null;
    final items = cached.byType(type);
    if (items.isEmpty) return null;
    return MediaQueue(
      items: items,
      type: type,
      startIndex: _startIndex(items, startUrl),
    );
  }

  /// Return a queue matching a given URL.
  MediaQueue? getQueueByUrl(String url, MediaType type) {
    for (final entry in _queues.entries) {
      final items = entry.value.byType(type);
      final idx = items.indexWhere((p) => p.url == url);
      if (idx >= 0) {
        return MediaQueue(items: items, type: type, startIndex: idx);
      }
    }
    return null;
  }

  // ---------- HELPERS ----------

  List<Playable> _buildPlayableList(ArchiveMediaInfo info, MediaType type) {
    final urls = (type == MediaType.video) ? info.videoUrls : info.audioUrls;

    final sorted = [...urls]..sort((a, b) {
      final A =
          Uri.parse(a).pathSegments.isNotEmpty
              ? Uri.parse(a).pathSegments.last.toLowerCase()
              : a.toLowerCase();
      final B =
          Uri.parse(b).pathSegments.isNotEmpty
              ? Uri.parse(b).pathSegments.last.toLowerCase()
              : b.toLowerCase();
      return A.compareTo(B);
    });

    String pretty(String u) {
      final mapped = info.displayNames[u];
      if (mapped != null && mapped.trim().isNotEmpty) return mapped;
      final segs = Uri.parse(u).pathSegments;
      return segs.isNotEmpty ? segs.last : u;
    }

    return sorted.map((u) => Playable(url: u, title: pretty(u))).toList();
  }

  int _startIndex(List<Playable> items, String? startUrl) {
    if (startUrl == null) return 0;

    final startName = Uri.parse(startUrl).pathSegments.last.toLowerCase();

    final i = items.indexWhere((p) {
      final name = Uri.parse(p.url).pathSegments.last.toLowerCase();
      return name == startName;
    });

    return i >= 0 ? i : 0;
  }
}
