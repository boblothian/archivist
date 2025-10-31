// lib/archive_item_loader.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<List<Map<String, String>>> fetchFilesForIdentifier(String identifier) async {
  final uri = Uri.https('archive.org', '/metadata/$identifier/files');

  try {
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return [];

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final List<dynamic> filesJson = json['result'] ?? [];

    final List<Map<String, String>> files = [];

    for (final f in filesJson) {
      final name = f['name'] as String?;
      final format = f['format'] as String?;
      final source = f['source'] as String?;

      if (name == null || format == null || source != 'original') continue;

      // Only include readable formats
      if (![
        'PDF',
        'EPUB',
        'MOBI',
        'TXT',
        'Daisy',
        'Kindle',
        'Comic Book ZIP',
        'DjVu',
      ].contains(format.toUpperCase())) {
        continue;
      }

      files.add({
        'name': name,
        'format': format,
        'url': 'https://archive.org/download/$identifier/$name',
      });
    }

    return files;
  } catch (e) {
    print('fetchFilesForIdentifier error: $e');
    return [];
  }
}