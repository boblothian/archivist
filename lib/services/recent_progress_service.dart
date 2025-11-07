// lib/services/recent_progress_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class RecentProgressService {
  RecentProgressService._();
  static final instance = RecentProgressService._();

  Box<dynamic>? _box;
  bool _isInitializing = false;

  final version = ValueNotifier<int>(0);
  void _notify() => version.value++;

  // --- Init lifecycle (memoized) ---
  late final Future<void> ready = _init();
  Future<void> init() => ready;

  Future<void> _init() async {
    if (_box != null && _box!.isOpen) return;
    if (_isInitializing) {
      // avoid busy spin; wait until done
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _isInitializing = true;
    try {
      _box =
          Hive.isBoxOpen('recent_progress')
              ? Hive.box<dynamic>('recent_progress')
              : await Hive.openBox<dynamic>('recent_progress');
    } catch (e) {
      debugPrint('RecentProgressService: openBox failed: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
    _notify(); // <-- trigger UI rebuild after cold start
  }

  // Keep for writers that may be called before init() has been awaited.
  Future<Box<dynamic>> _ensureBox() async {
    await init();
    return _box!;
  }

  // ----------------- Writers -----------------
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

  Future<void> remove(String id) async {
    final box = await _ensureBox();
    await box.delete(id);
    _notify();
  }

  // ----------------- Readers -----------------
  Map<String, dynamic>? get lastViewed {
    final box = _box;
    if (box == null || box.isEmpty) return null; // UI will rebuild after init()
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
}
