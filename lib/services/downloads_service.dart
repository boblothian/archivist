import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified downloads manager for Archivist:
/// - License-gated downloads (PD/CC only) via [isLicenseDownloadable]
/// - Actual downloading to app documents dir
/// - Tracks file paths per identifier
/// - Still supports your existing "reading_list" fallback
class DownloadsService {
  DownloadsService._();
  static final DownloadsService instance = DownloadsService._();

  // Keys for SharedPreferences
  static const _idSetKey = 'downloads_identifiers';
  static const _pathsMapKey = 'downloads_paths_map'; // JSON-ish via list join
  static const _readingListKey = 'reading_list';

  final Dio _dio = Dio();

  /// In-memory caches
  Set<String> _downloadedIds = {};

  /// identifier -> list of local file paths
  final Map<String, List<String>> _pathsById = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _downloadedIds =
        (prefs.getStringList(_idSetKey) ?? const <String>[]).toSet();

    // Load flattened map: we store keys like "$id|$index" -> path in a single list for simplicity
    final flat = prefs.getStringList(_pathsMapKey) ?? const <String>[];
    for (final line in flat) {
      final sep = line.indexOf('|');
      if (sep <= 0) continue;
      final id = line.substring(0, sep);
      final path = line.substring(sep + 1);
      _pathsById.putIfAbsent(id, () => []).add(path);
    }
  }

  /// Heuristic: allow offline saving for Public Domain / Creative Commons.
  /// Pass `license` and/or `rights` from your metadata.
  bool isLicenseDownloadable({String? license, String? rights}) {
    final l = ((license ?? rights) ?? '').toLowerCase();
    if (l.isEmpty) return false;
    return l.contains('public domain') ||
        l.contains('cc0') ||
        l.contains('creative commons') ||
        l.contains('cc-') ||
        l.contains('cc by') ||
        l.contains('cc-by') ||
        l.contains('cc-by-sa') ||
        l.contains('cc sa') ||
        l.contains('cc-sa') ||
        l.contains(
          'cc-nc',
        ); // okay to download with attribution; non-commercial use by the user
  }

  /// Returns true if we have recorded or inferred a download for this identifier.
  Future<bool> isDownloaded(String identifier) async {
    if (_downloadedIds.contains(identifier)) return true;
    if (_pathsById[identifier]?.isNotEmpty == true) return true;
    return _readingListContains(identifier);
  }

  /// Return local files previously saved for this identifier.
  List<String> getDownloadedFiles(String identifier) =>
      List.unmodifiable(_pathsById[identifier] ?? const []);

  /// Where we store media: <appDocs>/Archivist/downloads/<identifier>/
  Future<Directory> _dirFor(String identifier) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docs.path, 'Archivist', 'downloads', identifier),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Record a download (called automatically by [downloadMedia], but you can call it for PDFs, etc.)
  Future<void> recordDownloaded(
    String identifier, {
    String? localFilePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _downloadedIds.add(identifier);
    await prefs.setStringList(_idSetKey, _downloadedIds.toList());

    if (localFilePath != null) {
      _pathsById.putIfAbsent(identifier, () => []);
      if (!_pathsById[identifier]!.contains(localFilePath)) {
        _pathsById[identifier]!.add(localFilePath);
        await _persistPathsMap(prefs);
      }
    }
  }

  bool hasRecorded(String identifier) =>
      _downloadedIds.contains(identifier) ||
      (_pathsById[identifier]?.isNotEmpty == true);

  /// Download a media file to the app docs directory (under the identifier folder).
  /// - `onProgress(received, total)` gets called as bytes are written.
  /// - Returns the local file path.
  Future<String> downloadMedia({
    required String identifier,
    required String url,
    String? suggestedFileName,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _dirFor(identifier);

    final parsed = Uri.parse(url);
    // Derive a safe filename from URL or suggestion.
    String fileName =
        (suggestedFileName?.trim().isNotEmpty == true)
            ? suggestedFileName!.trim()
            : _filenameFromUrl(parsed);

    // Ensure unique name if it already exists.
    String savePath = p.join(dir.path, fileName);
    savePath = await _uniquePath(savePath);

    final resp = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
      ),
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );

    final file = File(savePath);
    final sink = file.openWrite();
    await resp.data!.stream.forEach((chunk) => sink.add(chunk));
    await sink.flush();
    await sink.close();

    await recordDownloaded(identifier, localFilePath: savePath);
    return savePath;
  }

  /// Remove all downloaded files for an identifier (and its record).
  Future<void> removeDownloads(String identifier) async {
    final prefs = await SharedPreferences.getInstance();

    final paths = _pathsById[identifier] ?? const [];
    for (final path in paths) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    // Also remove the directory if empty
    final dir = await _dirFor(identifier);
    try {
      if (await dir.exists()) {
        // Only delete if now empty
        if ((await dir.list().isEmpty)) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {}

    _pathsById.remove(identifier);
    _downloadedIds.remove(identifier);

    await prefs.setStringList(_idSetKey, _downloadedIds.toList());
    await _persistPathsMap(prefs);
  }

  /// Persist the identifier->paths map as flattened lines: "$id|$path"
  Future<void> _persistPathsMap(SharedPreferences prefs) async {
    final flat = <String>[];
    _pathsById.forEach((id, paths) {
      for (final path in paths) {
        flat.add('$id|$path');
      }
    });
    await prefs.setStringList(_pathsMapKey, flat);
  }

  /// Fallback: try to discover from reading_list filenames.
  Future<bool> _readingListContains(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final files = prefs.getStringList(_readingListKey) ?? const <String>[];
    for (final f in files) {
      final name = p.basename(f).toLowerCase();
      if (name.contains(identifier.toLowerCase())) return true;
    }
    return false;
  }

  String _filenameFromUrl(Uri url) {
    // Take last path segment, drop query, sanitize a bit
    var base = url.pathSegments.isNotEmpty ? url.pathSegments.last : 'media';
    // If it's empty or generic, provide a default extension guess
    if (base.isEmpty) base = 'media';
    // Remove any stray query-like suffixes
    base = base.split('?').first.split('#').first;
    // Minimal sanitization for filesystems
    base = base.replaceAll(RegExp(r'[^\w\.\-\(\)\[\] ]+'), '_');
    // Guard against no extension (HLS .m3u8 may be fine)
    return base;
  }

  Future<String> _uniquePath(String path) async {
    if (!await File(path).exists()) return path;
    final dir = p.dirname(path);
    final stem = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    int i = 1;
    while (await File(p.join(dir, '$stem ($i)$ext')).exists()) {
      i++;
    }
    return p.join(dir, '$stem ($i)$ext');
  }
}
