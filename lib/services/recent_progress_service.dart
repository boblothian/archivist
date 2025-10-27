import 'package:hive/hive.dart';

/// Stores last opened + reading progress for PDFs/EPUBs/videos.
/// Keyed by a stable id (e.g., Archive.org identifier or file path).
class RecentProgressService {
  RecentProgressService._();
  static final instance = RecentProgressService._();

  late Box _box; // key: id, value: Map<String, dynamic>

  Future<void> init() async {
    _box = await Hive.openBox('recent_progress');
  }

  /// Call whenever a thing is opened (collection, pdf, epub, video, etc).
  Future<void> touch({
    required String id,
    required String title,
    String? thumb,
    required String kind, // 'collection' | 'pdf' | 'epub' | 'video'
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = Map<String, dynamic>.from(_box.get(id) ?? {});
    prev.addAll({
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': kind,
      'lastOpenedAt': now,
    });
    await _box.put(id, prev);
  }

  /// Update PDF progress (1-based page + total)
  Future<void> updatePdf({
    required String id,
    required String title,
    String? thumb,
    required int page,
    required int total,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'pdf',
      'page': page,
      'total': total,
      'percent': total > 0 ? page / total : 0.0,
      'lastReadAt': now,
      'lastOpenedAt': now,
    });
  }

  /// Update EPUB progress (CFI + percent 0..1)
  Future<void> updateEpub({
    required String id,
    required String title,
    String? thumb,
    required String cfi,
    required double percent,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'epub',
      'cfi': cfi,
      'percent': percent,
      'lastReadAt': now,
      'lastOpenedAt': now,
    });
  }

  /// Most recent anything
  Map<String, dynamic>? get lastViewed {
    final values = _box.values;
    if (values.isEmpty) return null;
    final list = values.map((v) => Map<String, dynamic>.from(v)).toList();
    list.sort(
      (a, b) => (b['lastOpenedAt'] ?? 0).compareTo(a['lastOpenedAt'] ?? 0),
    );
    return list.first;
  }

  /// A short list for the “Previously viewed/watched” shelf
  List<Map<String, dynamic>> recent({int limit = 10}) {
    final list = _box.values.map((v) => Map<String, dynamic>.from(v)).toList();
    list.sort(
      (a, b) => (b['lastOpenedAt'] ?? 0).compareTo(a['lastOpenedAt'] ?? 0),
    );
    return list.take(limit).toList();
  }

  Map<String, dynamic>? getById(String id) {
    final v = _box.get(id);
    return v == null ? null : Map<String, dynamic>.from(v);
  }
}
