// lib/services/recent_progress_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'cloud_sync_service.dart';

class RecentProgressService {
  RecentProgressService._();
  static final instance = RecentProgressService._();

  Box<dynamic>? _box;
  bool _isInitializing = false;

  static const _kBoxName = 'recent_progress';
  static const _kSchemaVersionKey = '_schema_version';
  static const _kCurrentSchemaVersion = 2;

  final version = ValueNotifier<int>(0);
  void _notify() => version.value++;

  late final Future<void> ready = _init();
  Future<void> init() => ready;

  Future<void> _init() async {
    if (_box != null && _box!.isOpen) return;
    if (_isInitializing) {
      while (_isInitializing)
        await Future.delayed(const Duration(milliseconds: 50));
      return;
    }
    _isInitializing = true;
    try {
      _box =
          Hive.isBoxOpen(_kBoxName)
              ? Hive.box<dynamic>(_kBoxName)
              : await Hive.openBox<dynamic>(_kBoxName);

      final currentVersion = _box!.get(_kSchemaVersionKey) as int?;
      if (currentVersion == null || currentVersion < _kCurrentSchemaVersion) {
        debugPrint(
          'RecentProgress: Migrating schema v$currentVersion to v$_kCurrentSchemaVersion',
        );
        await _box!.clear();
        await _box!.put(_kSchemaVersionKey, _kCurrentSchemaVersion);
      }
    } catch (e) {
      debugPrint('RecentProgressService: openBox failed: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
    _notify();
  }

  Future<Box<dynamic>> _ensureBox() async {
    await init();
    return _box!;
  }

  // --- Writers ---
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
    _triggerImmediatePush();
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
    _triggerImmediatePush();
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
    _triggerImmediatePush();
  }

  Future<void> updateVideo({
    required String id,
    required String title,
    String? thumb,
    double? percent,
    required String fileUrl,
    required String fileName,
    int? positionMs,
    int? durationMs,
  }) async {
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;
    double finalPercent =
        (durationMs != null && durationMs > 0 && (positionMs ?? 0) >= 0)
            ? ((positionMs ?? 0) / durationMs)
            : (percent ?? 0.0);

    await box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'video',
      'percent': finalPercent,
      'fileUrl': fileUrl,
      'fileName': fileName,
      if (positionMs != null) 'positionMs': positionMs,
      if (durationMs != null) 'durationMs': durationMs,
      'lastOpenedAt': now,
      'lastWatchedAt': now,
    });
    _notify();
    _triggerImmediatePush();
  }

  Future<void> updateAudio({
    required String id,
    required String title,
    String? thumb,
    required String fileUrl,
    required String fileName,
    int? positionMs,
    int? durationMs,
    double? percent,
  }) async {
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;
    double finalPercent =
        (durationMs != null && durationMs > 0 && (positionMs ?? 0) >= 0)
            ? ((positionMs ?? 0) / durationMs)
            : (percent ?? 0.0);

    await box.put(id, {
      'id': id,
      'title': title,
      'thumb': thumb,
      'kind': 'audio',
      'percent': finalPercent,
      'fileUrl': fileUrl,
      'fileName': fileName,
      if (positionMs != null) 'positionMs': positionMs,
      if (durationMs != null) 'durationMs': durationMs,
      'lastOpenedAt': now,
      'lastListenedAt': now,
    });
    _notify();
    _triggerImmediatePush();
  }

  Future<void> upsertMedia({
    required String id,
    required String title,
    required String kind,
    String? thumb,
    required String fileUrl,
    String? fileName,
    int? positionMs,
    int? durationMs,
    double? percent,
  }) async {
    if (kind == 'video') {
      await updateVideo(
        id: id,
        title: title,
        thumb: thumb,
        fileUrl: fileUrl,
        fileName: fileName ?? '',
        positionMs: positionMs,
        durationMs: durationMs,
        percent: percent,
      );
    } else if (kind == 'audio') {
      await updateAudio(
        id: id,
        title: title,
        thumb: thumb,
        fileUrl: fileUrl,
        fileName: fileName ?? '',
        positionMs: positionMs,
        durationMs: durationMs,
        percent: percent,
      );
    } else {
      await touch(
        id: id,
        title: title,
        kind: kind,
        thumb: thumb,
        fileUrl: fileUrl,
        fileName: fileName,
      );
    }
  }

  /// Delete + immediate push
  Future<void> remove(String id) async {
    final box = await _ensureBox();
    await box.delete(id);
    _notify();
    _triggerImmediatePush(id);
  }

  // --- Readers ---
  Map<String, dynamic>? get lastViewed {
    final box = _box;
    if (box == null || box.isEmpty) return null;
    final list = box.values.map((v) => Map<String, dynamic>.from(v)).toList();
    list.sort(
      (a, b) => (b['lastOpenedAt'] ?? 0).compareTo(a['lastOpenedAt'] ?? 0),
    );
    return list.firstOrNull;
  }

  void _triggerImmediatePush([String? deletedId]) {
    CloudSyncService.instance.schedulePush(
      // ← public
      immediate: true,
      deletedId: deletedId,
    );
  }

  List<Map<String, dynamic>> recent({int limit = 10}) {
    final box = _box;
    if (box == null || box.isEmpty) return [];

    return box.values
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .where((map) {
          final id = map['id'];
          final title = map['title'];
          final lastOpenedAt = map['lastOpenedAt'];
          final kind = map['kind'] as String?;
          return id is String &&
              title is String &&
              lastOpenedAt is int &&
              kind is String &&
              _isValidKind(kind);
        })
        .toList()
      ..sort(
        (a, b) =>
            (b['lastOpenedAt'] as int).compareTo(a['lastOpenedAt'] as int),
      )
      ..take(limit);
  }

  Map<String, dynamic>? getById(String id) {
    final box = _box;
    if (box == null) return null;
    final v = box.get(id);
    return v == null ? null : Map<String, dynamic>.from(v);
  }

  static bool _isValidKind(String kind) {
    return const {
      'pdf',
      'epub',
      'cbz',
      'cbr',
      'txt',
      'video',
      'audio',
    }.contains(kind.toLowerCase());
  }
}
