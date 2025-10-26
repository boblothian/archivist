// lib/archive_api.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class ArchiveApi {
  static const String _host = 'archive.org';

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
                  title: (m['title'] ?? '') as String,
                  description: (m['description'] ?? '') as String,
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

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'ArchiveReader/1.0 (Flutter)',
  };
}

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
}
