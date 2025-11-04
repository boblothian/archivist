// lib/services/recent_progress_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class RecentProgressService {
  RecentProgressService._();
  static final instance = RecentProgressService._();

  // Lazy-loaded box
  Box? _box;
  bool _isInitializing = false;

  // REACTIVE NOTIFIER
  final version = ValueNotifier<int>(0);
  void _notify() => version.value++;

  /// Ensures the box is open — safe to call multiple times
  Future<Box> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    if (_isInitializing) {
      // Wait for ongoing init
      await Future.doWhile(
        () => _isInitializing,
      ).timeout(const Duration(seconds: 5));
      return _box!;
    }

    _isInitializing = true;
    try {
      _box = await Hive.openBox('recent_progress');
      return _box!;
    } catch (e) {
      debugPrint('RecentProgressService: Failed to open box: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize — now just a no-op (Hive.initFlutter() done in main.dart)
  Future<void> init() async {
    // No-op: box is opened lazily on first use
    // This allows startup to continue even if Hive isn't ready
  }

  /// First open — merge with existing
  Future<void> touch({
    required String id,
    required String title,
    String? thumb,
    required String kind,
    String? fileUrl,
    String? fileName,
  }) async {
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = Map<String, dynamic>.from(box.get(id) ?? {});
    prev.addAll({
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': kind,
      'lastOpenedAt': now,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (fileName != null) 'fileName': fileName,
    });
    await box.put(id, prev);
    _notify();
  }

  /// PDF page update
  Future<void> updatePdf({
    required String id,
    required String title,
    String? thumb,
    required int page,
    required int total,
    String? fileUrl,
    String? fileName,
  }) async {
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;
    await box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'pdf',
      'page': page,
      'total': total,
      'percent': total > 0 ? page / total : 0.0,
      'lastReadAt': now,
      'lastOpenedAt': now,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (fileName != null) 'fileName': fileName,
    });
    _notify();
  }

  /// EPUB progress
  Future<void> updateEpub({
    required String id,
    required String title,
    String? thumb,
    required int page,
    required int total,
    required double percent,
    required String cfi,
    String? fileUrl,
    String? fileName,
  }) async {
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;
    await box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'epub',
      'page': page,
      'total': total,
      'percent': percent,
      'cfi': cfi,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'lastOpenedAt': now,
      'lastReadAt': now,
    });
    _notify();
  }

  Future<void> remove(String id) async {
    final box = await _ensureBox();
    await box.delete(id);
    _notify();
  }

  Map<String, dynamic>? get lastViewed {
    final box = _box;
    if (box == null || box.isEmpty) return null;
    final list = box.values.map((v) => Map<String, dynamic>.from(v)).toList();
    list.sort(
      (a, b) => (b['lastOpenedAt'] ?? 0).compareTo(a['lastOpenedAt'] ?? 0),
    );
    return list.first;
  }

  List<Map<String, dynamic>> recent({int limit = 10}) {
    final box = _box;
    if (box == null || box.isEmpty) return [];
    final list = box.values.map((v) => Map<String, dynamic>.from(v)).toList();
    list.sort(
      (a, b) => (b['lastOpenedAt'] ?? 0).compareTo(a['lastOpenedAt'] ?? 0),
    );
    return list.take(limit).toList();
  }

  Map<String, dynamic>? getById(String id) {
    final box = _box;
    if (box == null) return null;
    final v = box.get(id);
    return v == null ? null : Map<String, dynamic>.from(v);
  }

  /// Video progress – percent-based (0.0 … 1.0)
  Future<void> updateVideo({
    required String id,
    required String title,
    String? thumb,
    required double percent,
    required String fileUrl,
    required String fileName,
  }) async {
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;
    await box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'video',
      'percent': percent,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'lastOpenedAt': now,
      'lastWatchedAt': now,
    });
    _notify();
  }
}
