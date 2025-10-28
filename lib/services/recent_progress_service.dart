// lib/services/recent_progress_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class RecentProgressService {
  RecentProgressService._();
  static final instance = RecentProgressService._();

  late Box _box;

  // REACTIVE NOTIFIER
  final version = ValueNotifier<int>(0);
  void _notify() => version.value++;

  Future<void> init() async {
    _box = await Hive.openBox('recent_progress');
    _notify();
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = Map<String, dynamic>.from(_box.get(id) ?? {});
    prev.addAll({
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': kind,
      'lastOpenedAt': now,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (fileName != null) 'fileName': fileName,
    });
    await _box.put(id, prev);
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
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (fileName != null) 'fileName': fileName,
    });
    _notify();
  }

  /// EPUB progress – FIXED: uses Hive, same key
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
    final now = DateTime.now().millisecondsSinceEpoch;
    await _box.put(id, {
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
    await _box.delete(id);
    _notify();
  }

  Map<String, dynamic>? get lastViewed {
    final values = _box.values;
    if (values.isEmpty) return null;
    final list = values.map((v) => Map<String, dynamic>.from(v)).toList();
    list.sort(
      (a, b) => (b['lastOpenedAt'] ?? 0).compareTo(a['lastOpenedAt'] ?? 0),
    );
    return list.first;
  }

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

  /// Video progress – percent-based (0.0 … 1.0)
  Future<void> updateVideo({
    required String id,
    required String title,
    String? thumb,
    required double percent,
    required String fileUrl,
    required String fileName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _box.put(id, {
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
