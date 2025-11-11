// lib/services/thumbnail_service.dart
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../net.dart';
import '../utils/archive_helpers.dart';
import 'thumb_override_service.dart';
import 'tmdb_service.dart';

class ThumbnailService {
  static final ThumbnailService _instance = ThumbnailService._();
  factory ThumbnailService() => _instance;
  ThumbnailService._();

  // Cache for gather calls
  final Map<String, List<String>> _posterCache = {};

  /// Smart fallback chain for thumbnail
  Future<String> getSmartThumb({
    required String id,
    required String mediatype,
    required String title,
    String? year,
  }) async {
    final itemImage = await _fetchItemImage(id);
    if (itemImage != null) return itemImage;

    if (mediatype.toLowerCase().contains('video') || mediatype == 'movies') {
      final poster = await TmdbService.getPosterUrl(title: title, type: '');
      if (poster != null) return poster;
    }

    if (mediatype.toLowerCase().contains('video')) {
      return 'https://archive.org/download/$id/${id}__thumb.jpg';
    }

    return archiveThumbUrl(id);
  }

  /// Fetch itemimage from metadata
  Future<String?> _fetchItemImage(String id) async {
    try {
      final resp = await http.get(
        Uri.parse('https://archive.org/metadata/$id'),
        headers: Net.headers,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final itemImage = data['metadata']?['itemimage']?.toString();
        if (itemImage != null && itemImage.isNotEmpty) {
          return 'https://archive.org/services/img/$itemImage';
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>> gatherPosterCandidates({
    required String query,
    required String id,
    required String mediatype,
    String? year,
    bool allowArchive = false,
  }) async {
    final cacheKey = '$query|$id|$year';
    if (_posterCache.containsKey(cacheKey)) {
      return _posterCache[cacheKey]!;
    }

    final nonArchive = <String>[];
    final archive = <String>[];

    void add(String? u) {
      if (u == null || u.trim().isEmpty) return;
      final s = u.trim();
      final isArchive = Uri.tryParse(s)?.host.contains('archive.org') ?? false;
      (isArchive ? archive : nonArchive).add(s);
    }

    // 1. Archive.org
    await _addArchiveCandidates(id, archive, add);

    // 2. TMDb
    final results = await TmdbService.search(query: query, year: year);
    for (final r in results) {
      add(r.posterUrl);
      // Add higher-res versions
      add(r.posterUrl.replaceAll('/w500', '/original'));
    }

    // 3. Upscale
    final upsized = <String>[];
    for (final u in nonArchive) {
      final up = u
          .replaceAll('/w342/', '/w500/')
          .replaceAll('/w500/', '/w780/')
          .replaceAll('/w780/', '/original/');
      if (up != u) upsized.add(up);
    }
    nonArchive.addAll(upsized);

    List<String> dedupe(List<String> xs) {
      final seen = <String>{};
      return xs.where(seen.add).toList();
    }

    final out = dedupe(nonArchive).take(24).toList();
    if (out.isNotEmpty) {
      _posterCache[cacheKey] = out;
      return out;
    }

    final arch = dedupe(archive);
    final fallback =
        allowArchive ? arch.take(12).toList() : arch.take(2).toList();
    _posterCache[cacheKey] = fallback;
    return fallback;
  }

  Future<void> _addArchiveCandidates(
    String id,
    List<String> archive,
    void Function(String?) add,
  ) async {
    try {
      final resp = await http.get(
        Uri.parse('https://archive.org/metadata/$id'),
        headers: Net.headers,
      );
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body);
      final meta = data['metadata'] ?? {};
      final files = data['files'] ?? [];

      final itemImage = meta['itemimage']?.toString();
      if (itemImage != null && itemImage.isNotEmpty) {
        add('https://archive.org/services/img/$itemImage');
      }

      final imageFiles = <String>[];
      for (final f in files) {
        if (f is! Map) continue;
        final name = f['name']?.toString() ?? '';
        final fmt = (f['format']?.toString() ?? '').toLowerCase();
        if (name.isEmpty) continue;
        final isImage =
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp') ||
            name.endsWith('.gif') ||
            fmt.contains('jpeg') ||
            fmt.contains('png');
        if (isImage) imageFiles.add(name);
      }

      final pri = <String>[];
      final sec = <String>[];
      const priNames = ['cover', 'poster', 'front', 'thumb', '00', '000'];
      for (final n in imageFiles) {
        final hit = priNames.any((k) => n.toLowerCase().contains(k));
        (hit ? pri : sec).add(n);
      }

      for (final n in [...pri, ...sec].take(10)) {
        add('https://archive.org/download/$id/${Uri.encodeComponent(n)}');
      }
    } catch (_) {}

    // Fallbacks
    archive.add('https://archive.org/services/img/$id');
    archive.add('https://archive.org/download/$id/${id}__thumb.jpg');
    archive.add(archiveThumbUrl(id));
  }

  /// Rich chooser with TMDb metadata
  Future<String?> choosePosterRich(
    BuildContext context,
    String query, {
    String? year,
    String? currentTitle,
  }) async {
    final results = await TmdbService.search(query: query, year: year);
    if (results.isEmpty) return null;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _TmdbPosterPicker(
            results: results,
            currentTitle: currentTitle ?? query,
          ),
    );
  }

  /// Enrich item map with TMDb data
  Future<void> enrichItemWithTmdb(Map<String, String> item) async {
    final title = item['title'] ?? '';
    final year = item['year'];
    final id = item['identifier']!;

    if (title.isEmpty) return;

    final results = await TmdbService.search(query: title, year: year);
    if (results.isEmpty) return;

    final best = results.first;
    final updated = <String, String>{
      ...item,
      'title': best.title,
      'description': best.overview ?? item['description'] ?? '',
      'creator': best.genres.join(', '),
      'year': best.year,
      'thumb': best.posterUrl,
    };

    // Apply override
    await ThumbOverrideService.instance.set(id, best.posterUrl);

    // Update in-place
    item
      ..clear()
      ..addAll(updated);
  }
}

// ──────────────────────────────────────────────
// Rich Poster Picker Widget
// ──────────────────────────────────────────────
class _TmdbPosterPicker extends StatelessWidget {
  final List<TmdbResult> results;
  final String currentTitle;

  const _TmdbPosterPicker({required this.results, required this.currentTitle});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Pick thumbnail for "$currentTitle"',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (_, i) {
                final r = results[i];
                return _TmdbResultTile(
                  result: r,
                  onTap: () => Navigator.pop(context, r.posterUrl),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _TmdbResultTile extends StatelessWidget {
  final TmdbResult result;
  final VoidCallback onTap;

  const _TmdbResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: result.posterUrl,
                width: 60,
                height: 90,
                fit: BoxFit.cover,
                placeholder:
                    (_, _) => Container(color: cs.surfaceContainerHighest),
                errorWidget: (_, _, _) => const Icon(Icons.broken_image),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.year.isNotEmpty)
                    Text(
                      result.year,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (result.voteAverage != null)
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${result.voteAverage!.toStringAsFixed(1)} (${result.voteCount})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  if (result.genres.isNotEmpty)
                    Text(
                      result.genres.take(3).join(', '),
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
