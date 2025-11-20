import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../archive_api.dart';

class DiscogsService {
  DiscogsService._();
  static final instance = DiscogsService._();

  static const _base = 'https://api.discogs.com';
  static const _token = 'UZMUkdEhCTbIpEXCpcCLHtiRNBpzZJRiHdRBGeUO';
  static const _userAgent = 'ArchivistApp/1.0 +https://your-site';

  final http.Client _client = http.Client();

  // ---------------------------------------------------------------------------
  // PUBLIC: save album order for an Archive item (used by "Order album" button)
  // ---------------------------------------------------------------------------
  Future<void> saveAlbumOrderForItem({
    required String identifier,
    required String albumTitle,
    String? artist,
    String? year,
  }) async {
    final rel = await findRelease(
      artist: artist ?? '',
      title: albumTitle,
      year: year,
    );
    if (rel == null || rel.tracks.isEmpty) {
      throw Exception('No matching Discogs release');
    }

    // Fetch archive files for this identifier
    final files = await ArchiveApi.fetchFilesForIdentifier(identifier);
    final audioFiles =
        files.where((f) {
          final name = (f['name'] ?? '').toString().toLowerCase();
          final fmt = (f['format'] ?? '').toString().toLowerCase();
          if (name.isEmpty) return false;
          final isAudio =
              fmt.contains('mp3') ||
              fmt.contains('ogg') ||
              fmt.contains('flac') ||
              fmt.contains('wav') ||
              fmt.contains('audio') ||
              name.endsWith('.mp3') ||
              name.endsWith('.ogg') ||
              name.endsWith('.oga') ||
              name.endsWith('.flac') ||
              name.endsWith('.wav') ||
              name.endsWith('.aac') ||
              name.endsWith('.m4a');
          return isAudio;
        }).toList();

    if (audioFiles.isEmpty) {
      throw Exception('No audio files to order');
    }

    String normalize(String s) {
      s = s.toLowerCase();
      // strip extension
      final dot = s.lastIndexOf('.');
      if (dot > 0) s = s.substring(0, dot);
      // strip leading track numbers like "01 - " or "1. "
      s = s.replaceFirst(RegExp(r'^\s*\d+[\s\.\-_]+'), '');
      // collapse spaces / separators
      s = s.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
      return s;
    }

    // map Discogs track title -> index
    final Map<String, int> discogsIndex = {};
    for (int i = 0; i < rel.tracks.length; i++) {
      final t = rel.tracks[i];
      final norm = normalize(t.title);
      if (norm.isEmpty) continue;
      discogsIndex.putIfAbsent(norm, () => i);
    }

    final List<MapEntry<String, int>> matches = [];
    for (final f in audioFiles) {
      final name = (f['name'] ?? '').toString();
      final norm = normalize(name);
      if (norm.isEmpty) continue;
      final idx = discogsIndex[norm];
      if (idx != null) {
        matches.add(MapEntry<String, int>(name, idx));
      } else {
        // unmatched tracks go to the end, but keep a stable relative order
        matches.add(MapEntry<String, int>(name, 100000 + matches.length));
      }
    }

    matches.sort((a, b) => a.value.compareTo(b.value));
    final orderedFilenames = matches.map((e) => e.key).toList(growable: false);

    await _saveOrder(identifier, orderedFilenames);
  }

  // ---------------------------------------------------------------------------
  // PUBLIC: apply saved order to [{name: ...}] maps (used by ArchiveItemScreen)
  // ---------------------------------------------------------------------------
  Future<List<Map<String, String>>> applySavedOrderToFiles({
    required String identifier,
    required List<Map<String, String>> files,
  }) async {
    final order = await _loadOrder(identifier);
    if (order == null || order.isEmpty) return files;

    final Map<String, int> index = {};
    for (int i = 0; i < order.length; i++) {
      index[order[i]] = i;
    }

    final sorted = List<Map<String, String>>.from(files);
    sorted.sort((a, b) {
      final aName = (a['name'] ?? '');
      final bName = (b['name'] ?? '');
      final ai = index[aName];
      final bi = index[bName];
      if (ai == null && bi == null) return 0;
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });

    return sorted;
  }

  // ---------------------------------------------------------------------------
  // PUBLIC: sort audioFiles (List<Map<String,dynamic>>) IN PLACE
  // Called from CollectionDetailScreen before pushing ArchiveItemScreen
  // ---------------------------------------------------------------------------
  Future<void> sortAudioFilesForItem({
    required String identifier,
    required List<Map<String, dynamic>> files,
  }) async {
    // build a lightweight [{name: ...}] list
    final simple =
        files
            .map<Map<String, String>>(
              (f) => {'name': (f['name'] ?? '').toString()},
            )
            .toList();

    final orderedSimple = await applySavedOrderToFiles(
      identifier: identifier,
      files: simple,
    );

    // name -> index
    final idxMap = <String, int>{};
    for (int i = 0; i < orderedSimple.length; i++) {
      idxMap[orderedSimple[i]['name'] ?? ''] = i;
    }

    files.sort((a, b) {
      final aName = (a['name'] ?? '').toString();
      final bName = (b['name'] ?? '').toString();
      final ai = idxMap[aName];
      final bi = idxMap[bName];
      if (ai == null && bi == null) return 0;
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });
  }

  // ---------------------------------------------------------------------------
  // PUBLIC: show a Discogs cover picker & return chosen URL
  // Used by chooseAlbumArtRich in long-press dialog
  // ---------------------------------------------------------------------------
  Future<String?> chooseAlbumArtRich({
    required BuildContext context,
    required String albumTitle,
    String? artist,
    String? year,
  }) async {
    // 1) Search Discogs for candidate releases
    final params = <String, String>{
      'release_title': albumTitle,
      'type': 'release',
      'token': _token,
    };
    if (artist != null && artist.trim().isNotEmpty) {
      params['artist'] = artist.trim();
    }
    final uri = Uri.parse(
      '$_base/database/search',
    ).replace(queryParameters: params);

    final resp = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (resp.statusCode != 200) {
      throw Exception('Discogs search failed (${resp.statusCode})');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (json['results'] as List?) ?? const [];
    if (results.isEmpty) return null;

    final candidates =
        results
            .whereType<Map>()
            .map((r) {
              final title = (r['title'] ?? '').toString();
              final thumb = (r['cover_image'] ?? '').toString();
              final yearStr = (r['year'] ?? '').toString();
              return _DiscogsChoice(
                title: title,
                thumbUrl: thumb,
                year: yearStr,
              );
            })
            .where((c) => c.thumbUrl.isNotEmpty)
            .toList();

    if (candidates.isEmpty) return null;

    // 2) Let the user pick one in a bottom sheet
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pick Discogs cover',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${candidates.length}',
                        style: Theme.of(ctx).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = candidates[i];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: c.thumbUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          c.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle:
                            c.year.isNotEmpty ? Text('Year: ${c.year}') : null,
                        onTap: () {
                          Navigator.of(ctx).pop(c.thumbUrl);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // INTERNAL: store/retrieve orders
  // ---------------------------------------------------------------------------
  static const _prefsKey = 'discogs_album_orders';

  Future<void> _saveOrder(String identifier, List<String> filenames) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final Map<String, dynamic> map =
        raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>);
    map[identifier] = filenames;
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  Future<List<String>?> _loadOrder(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final v = map[identifier];
    if (v is List) {
      return v.map((e) => e.toString()).toList();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // BASIC release fetch used by saveAlbumOrderForItem (first matching release)
  // ---------------------------------------------------------------------------
  Future<_DiscogsRelease?> findRelease({
    required String artist,
    required String title,
    String? year,
  }) async {
    final params = <String, String>{
      'release_title': title,
      'type': 'release',
      'token': _token,
    };
    if (artist.trim().isNotEmpty) {
      params['artist'] = artist.trim();
    }
    final uri = Uri.parse(
      '$_base/database/search',
    ).replace(queryParameters: params);

    final resp = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (json['results'] as List?) ?? const [];
    if (results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final id = first['id'] as int?;
    final img = first['cover_image'] as String?;
    if (id == null) return null;

    final relResp = await _client.get(
      Uri.parse('$_base/releases/$id?token=$_token'),
      headers: {'User-Agent': _userAgent},
    );
    if (relResp.statusCode != 200) return null;

    final relJson = jsonDecode(relResp.body) as Map<String, dynamic>;
    final tracks = (relJson['tracklist'] as List?) ?? const [];

    return _DiscogsRelease(
      coverImage: img,
      tracks:
          tracks
              .whereType<Map>()
              .map(
                (t) => _DiscogsTrack(
                  title: (t['title'] ?? '').toString(),
                  position: (t['position'] ?? '').toString(),
                ),
              )
              .toList(),
    );
  }
}

class _DiscogsRelease {
  final String? coverImage;
  final List<_DiscogsTrack> tracks;
  _DiscogsRelease({this.coverImage, required this.tracks});
}

class _DiscogsTrack {
  final String title;
  final String position;
  _DiscogsTrack({required this.title, required this.position});
}

class _DiscogsChoice {
  final String title;
  final String thumbUrl;
  final String year;
  _DiscogsChoice({
    required this.title,
    required this.thumbUrl,
    required this.year,
  });
}
