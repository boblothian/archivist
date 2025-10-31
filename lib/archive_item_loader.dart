// utils/archive_item_loader.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'net.dart'; // <-- your Net.headers

Future<List<Map<String, String>>> fetchFilesForIdentifier(
  String identifier,
) async {
  final url = 'https://archive.org/metadata/$identifier/metadata';
  final resp = await http.get(Uri.parse(url), headers: Net.headers);
  if (resp.statusCode != 200) throw Exception('metadata failed');

  final json = jsonDecode(resp.body) as Map<String, dynamic>;
  final filesJson = json['files'] as List<dynamic>? ?? [];

  return filesJson
      .cast<Map<String, dynamic>>()
      .map((f) => f.map((k, v) => MapEntry(k, v.toString())))
      .toList();
}
