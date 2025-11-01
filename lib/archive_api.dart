// lib/archive_api.dart
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class ArchiveApi {
  static const String _host = 'archive.org';

  // =================================================================
  // SEARCH COLLECTIONS
  // =================================================================
  static Future<List<ArchiveCollection>> searchCollections(
    String query, {
    int rows = 50,
    int page = 1,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return _searchPopular(rows);
    return _searchKeyword(q, rows, page);
  }

  static Future<List<ArchiveCollection>> _searchPopular(int rows) async {
    final uri = Uri.https(_host, '/advancedsearch.php').replace(
      queryParameters: {
        'q': 'mediatype:collection',
        'fl[]': ['identifier', 'title', 'description', 'downloads'],
        'rows': rows.toString(),
        'page': '1',
        'output': 'json',
        'sort[]': 'downloads desc',
      },
    );
    return _fetchAndParse(uri);
  }

  static Future<List<ArchiveCollection>> _searchKeyword(
    String keyword,
    int rows,
    int page,
  ) async {
    final safe = keyword.trim();
    final queryParts = [
      'title:"$safe"',
      'subject:"$safe"',
      'description:"$safe"',
      'creator:"$safe"',
      'identifier:"$safe"',
    ];
    final lucene = '(${queryParts.join(' OR ')}) AND mediatype:collection';

    final uri = Uri.https(_host, '/advancedsearch.php').replace(
      queryParameters: {
        'q': lucene,
        'fl[]': ['identifier', 'title', 'description', 'downloads'],
        'rows': rows.toString(),
        'page': page.toString(),
        'output': 'json',
        'sort[]': 'downloads desc',
      },
    );

    print('Search URL: $uri');
    return _fetchAndParse(uri);
  }

  // =================================================================
  // FETCH SINGLE COLLECTION BY ID
  // =================================================================
  /// Fetches a single collection's metadata using archive.org/metadata
  static Future<ArchiveCollection> getCollection(String identifier) async {
    if (identifier.trim().isEmpty) {
      throw ArgumentError('Identifier cannot be empty');
    }

    final id = identifier.trim();
    final uri = Uri.https(_host, '/metadata/$id');

    final resp = await http.get(uri, headers: _headers);

    if (resp.statusCode != 200) {
      throw Exception('Failed to load collection "$id": ${resp.statusCode}');
    }

    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final metadata = (json['metadata'] as Map<String, dynamic>?) ?? {};

      final title = _flat(metadata['title']) ?? '';
      final description = _flat(metadata['description']) ?? '';

      return ArchiveCollection(
        identifier: id,
        title: title,
        description: description,
        downloads: _asInt(metadata['downloads']),
        thumbnailUrl: 'https://archive.org/services/img/$id',
      );
    } catch (e) {
      throw Exception('Failed to parse collection "$id": $e');
    }
  }

  // =================================================================
  // GENERIC METADATA FETCH
  // =================================================================
  /// Generic metadata fetch – works for **any** identifier (item or collection)
  static Future<Map<String, dynamic>> getMetadata(String identifier) async {
    if (identifier.trim().isEmpty) {
      throw ArgumentError('Identifier cannot be empty');
    }

    final id = identifier.trim();
    final uri = Uri.https(_host, '/metadata/$id');

    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load metadata for "$id": ${resp.statusCode}');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Returns true if the identifier points to a *collection*
  static Future<bool> isCollection(String identifier) async {
    try {
      final meta = await getMetadata(identifier);
      final mediatype = _flat(meta['metadata']?['mediatype']) ?? '';
      return mediatype.toLowerCase() == 'collection';
    } catch (_) {
      return false; // assume item on error
    }
  }

  // =================================================================
  // FETCH DOWNLOADABLE FILES FOR AN ITEM
  // =================================================================
  static Future<List<Map<String, String>>> fetchFilesForIdentifier(
    String id,
  ) async {
    if (id.trim().isEmpty) return [];

    final identifier = id.trim();
    debugPrint('fetchFilesForIdentifier → metadata/$identifier');

    try {
      // Use the stable Metadata API
      final meta = await getMetadata(identifier);
      final files = (meta['files'] as List?) ?? const [];

      final result = <Map<String, String>>[];

      for (final f in files) {
        if (f is! Map) continue;

        final name = (f['name'] as String?) ?? '';
        if (name.isEmpty) continue;

        final format = (f['format'] as String?) ?? '';
        final sizeStr = f['size']?.toString() ?? '0';

        if (_isDownloadableFormat(format, name)) {
          result.add({
            'name': name,
            'url':
                'https://archive.org/download/$identifier/${Uri.encodeComponent(name)}',
            'size': _formatSize(sizeStr),
            'fmt': format,
            'pretty': _prettyName(name),
          });
        }
      }

      debugPrint('Found ${result.length} downloadable files for $identifier');
      return result;
    } catch (e) {
      debugPrint('fetchFilesForIdentifier ERROR ($id): $e');
      return [];
    }
  }

  // =================================================================
  // SHARED PARSING LOGIC
  // =================================================================
  static Future<List<ArchiveCollection>> _fetchAndParse(Uri uri) async {
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      print('HTTP ${resp.statusCode}: ${resp.body}');
      return [];
    }

    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final docs = (json['response']?['docs'] as List?) ?? [];

      final results =
          docs
              .map((d) {
                final m = d as Map<String, dynamic>;
                final identifier = (m['identifier'] ?? '') as String;

                final thumbnail =
                    identifier.isNotEmpty
                        ? 'https://archive.org/services/img/$identifier'
                        : null;

                return ArchiveCollection(
                  identifier: identifier,
                  title: _flat(m['title']) ?? '',
                  description: _flat(m['description']) ?? '',
                  downloads: _asInt(m['downloads']),
                  thumbnailUrl: thumbnail,
                );
              })
              .where((c) => c.identifier.isNotEmpty)
              .toList();

      print('Found ${results.length} collections');
      return results;
    } catch (e) {
      print('JSON error: $e');
      return [];
    }
  }

  // =================================================================
  // HELPERS
  // =================================================================
  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String? _flat(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      return v.whereType<String>().join(', ');
    }
    return v.toString();
  }

  static bool _isDownloadableFormat(String format, String name) {
    final allowedFormats = {
      'PDF',
      'EPUB',
      'CBZ',
      'CBR',
      'MPEG4',
      'H.264',
      'WebM',
      'Matroska',
      'Text',
      'DjVu',
      'Kindle',
      'Comic Book ZIP',
      'Comic Book RAR',
    };
    if (allowedFormats.contains(format)) return true;

    final ext = name.split('.').lastOrNull?.toLowerCase() ?? '';
    return [
      'pdf',
      'epub',
      'cbz',
      'cbr',
      'mp4',
      'mkv',
      'webm',
      'txt',
      'djvu',
    ].contains(ext);
  }

  static String _formatSize(String sizeStr) {
    final bytes = int.tryParse(sizeStr) ?? 0;
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[i]}';
  }

  static String _prettyName(String name) {
    return name
        .replaceAll('.ia.', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'ArchiveReader/1.0 (Flutter)',
  };
}

// =================================================================
// MODEL (outside the class)
// =================================================================
class ArchiveCollection {
  final String identifier;
  final String title;
  final String description;
  final int downloads;
  final String? thumbnailUrl;

  const ArchiveCollection({
    required this.identifier,
    required this.title,
    required this.description,
    required this.downloads,
    this.thumbnailUrl,
  });

  @override
  String toString() {
    return 'ArchiveCollection(identifier: $identifier, title: $title, downloads: $downloads)';
  }
}
