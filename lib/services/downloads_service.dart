import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Best-effort "downloaded" detector:
/// - First: use a stored set of downloaded identifiers (if you record them)
/// - Fallback: try to infer from 'reading_list' (file paths) that contain the identifier
class DownloadsService {
  DownloadsService._();
  static final DownloadsService instance = DownloadsService._();

  static const _idSetKey = 'downloads_identifiers';
  static const _readingListKey = 'reading_list';

  Set<String> _downloadedIds = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _downloadedIds =
        (prefs.getStringList(_idSetKey) ?? const <String>[]).toSet();
    // No heavy scanning here; we’ll use reading_list as a fallback in [isDownloaded]
  }

  /// Call this where you save a file (PDF/EPUB/CBZ) for an item.
  Future<void> recordDownloaded(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    _downloadedIds.add(identifier);
    await prefs.setStringList(_idSetKey, _downloadedIds.toList());
  }

  bool hasRecorded(String identifier) => _downloadedIds.contains(identifier);

  /// Fallback: try to discover from reading_list filenames.
  Future<bool> _readingListContains(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final files = prefs.getStringList(_readingListKey) ?? const <String>[];
    // loose match: filename often starts with or contains the identifier
    for (final f in files) {
      final name = p.basename(f).toLowerCase();
      if (name.contains(identifier.toLowerCase())) return true;
    }
    return false;
  }

  Future<bool> isDownloaded(String identifier) async {
    if (_downloadedIds.contains(identifier)) return true;
    return _readingListContains(identifier);
  }
}
