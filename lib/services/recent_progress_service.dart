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
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
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

  // ---------------------------------------------------------------------------
  // Helper to choose the *best* thumbnail
  // ---------------------------------------------------------------------------
  String _bestThumb({
    required String id,
    required String kind,
    String? newThumb,
    String? fileName,
    String? prevThumb,
  }) {
    // 1) If caller explicitly passes a thumb, always prefer that
    if (newThumb != null && newThumb.trim().isNotEmpty) {
      return newThumb.trim();
    }

    final lowerKind = kind.toLowerCase();
    final name = fileName ?? '';
    final lowerName = name.toLowerCase();

    // 2) Derive from fileName for reading types (PDF, images, etc.)
    if (name.isNotEmpty) {
      // PDF: use JP2 first-page thumbnail, same style as ArchiveItemScreen
      if (lowerName.endsWith('.pdf')) {
        final base = name.substring(0, name.length - 4); // strip '.pdf'
        final encoded = Uri.encodeComponent(base);
        return 'https://archive.org/download/$id/'
            '$encoded'
            '_jp2.zip/'
            '$encoded'
            '_jp2/'
            '$encoded'
            '_0000.jp2&ext=jpg';
      }

      // Direct image file → use its own URL as thumb
      if (lowerName.endsWith('.jpg') ||
          lowerName.endsWith('.jpeg') ||
          lowerName.endsWith('.png') ||
          lowerName.endsWith('.gif') ||
          lowerName.endsWith('.webp')) {
        final encodedName = Uri.encodeComponent(name);
        return 'https://archive.org/download/$id/$encodedName';
      }
    }

    // 3) Keep previous thumb if we had one
    if (prevThumb != null && prevThumb.toString().trim().isNotEmpty) {
      return prevThumb.toString();
    }

    // 4) Absolute fallback → collection/item thumb
    return 'https://archive.org/services/img/$id';
  }

  // --- Writers ---------------------------------------------------------------

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
    final effectiveThumb = _bestThumb(
      id: id,
      kind: kind,
      newThumb: thumb,
      fileName: fileName,
      prevThumb: prev['thumb'] as String?,
    );

    prev
      ..['id'] = id
      ..['title'] = title
      ..['thumb'] = effectiveThumb
      ..['kind'] = kind
      ..['lastOpenedAt'] = now;

    if (fileUrl != null) prev['fileUrl'] = fileUrl;
    if (fileName != null) prev['fileName'] = fileName;

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
    const kind = 'pdf';
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;

    final prev = Map<String, dynamic>.from(box.get(id) ?? {});
    final effectiveThumb = _bestThumb(
      id: id,
      kind: kind,
      newThumb: thumb,
      fileName: fileName ?? prev['fileName'] as String?,
      prevThumb: prev['thumb'] as String?,
    );

    prev
      ..['id'] = id
      ..['title'] = title
      ..['thumb'] = effectiveThumb
      ..['kind'] = kind
      ..['page'] = page
      ..['total'] = total
      ..['percent'] = total > 0 ? page / total : 0.0
      ..['lastReadAt'] = now
      ..['lastOpenedAt'] = now;

    if (fileUrl != null) prev['fileUrl'] = fileUrl;
    if (fileName != null) prev['fileName'] = fileName;

    await box.put(id, prev);
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
    const kind = 'epub';
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;

    final prev = Map<String, dynamic>.from(box.get(id) ?? {});
    final effectiveThumb = _bestThumb(
      id: id,
      kind: kind,
      newThumb: thumb,
      fileName: fileName ?? prev['fileName'] as String?,
      prevThumb: prev['thumb'] as String?,
    );

    prev
      ..['id'] = id
      ..['title'] = title
      ..['thumb'] = effectiveThumb
      ..['kind'] = kind
      ..['page'] = page
      ..['total'] = total
      ..['percent'] = percent
      ..['cfi'] = cfi
      ..['lastOpenedAt'] = now
      ..['lastReadAt'] = now;

    if (fileUrl != null) prev['fileUrl'] = fileUrl;
    if (fileName != null) prev['fileName'] = fileName;

    await box.put(id, prev);
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
    const kind = 'video';
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;

    final prev = Map<String, dynamic>.from(box.get(id) ?? {});
    final effectiveThumb = _bestThumb(
      id: id,
      kind: kind,
      newThumb: thumb,
      fileName: fileName,
      prevThumb: prev['thumb'] as String?,
    );

    double finalPercent;
    if (durationMs != null && durationMs > 0 && (positionMs ?? 0) >= 0) {
      finalPercent = (positionMs ?? 0) / durationMs;
    } else {
      finalPercent =
          percent ??
          (prev['percent'] is num ? (prev['percent'] as num).toDouble() : 0.0);
    }

    prev
      ..['id'] = id
      ..['title'] = title
      ..['thumb'] = effectiveThumb
      ..['kind'] = kind
      ..['percent'] = finalPercent
      ..['fileUrl'] = fileUrl
      ..['fileName'] = fileName
      ..['lastOpenedAt'] = now
      ..['lastWatchedAt'] = now;

    if (positionMs != null) prev['positionMs'] = positionMs;
    if (durationMs != null) prev['durationMs'] = durationMs;

    await box.put(id, prev);
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
    List<String>? queueUrls,
    Map<String, String>? queueTitles,
    Map<String, String>? queueThumbnails,
    String? currentTrackUrl,
  }) async {
    const kind = 'audio';
    final box = await _ensureBox();
    final now = DateTime.now().millisecondsSinceEpoch;

    final prev = Map<String, dynamic>.from(box.get(id) ?? {});
    final effectiveThumb = _bestThumb(
      id: id,
      kind: kind,
      newThumb: thumb,
      fileName: fileName,
      prevThumb: prev['thumb'] as String?,
    );

    double finalPercent;
    if (durationMs != null && durationMs > 0 && (positionMs ?? 0) >= 0) {
      finalPercent = (positionMs ?? 0) / durationMs;
    } else {
      finalPercent =
          percent ??
          (prev['percent'] is num ? (prev['percent'] as num).toDouble() : 0.0);
    }

    prev
      ..['id'] = id
      ..['title'] = title
      ..['thumb'] = effectiveThumb
      ..['kind'] = kind
      ..['percent'] = finalPercent
      ..['fileUrl'] = fileUrl
      ..['fileName'] = fileName
      ..['lastOpenedAt'] = now
      ..['lastListenedAt'] = now;

    if (positionMs != null) prev['positionMs'] = positionMs;
    if (durationMs != null) prev['durationMs'] = durationMs;

    if (queueUrls != null) prev['queueUrls'] = queueUrls;
    if (queueTitles != null) {
      prev['queueTitles'] = Map<String, dynamic>.from(queueTitles);
    }
    if (queueThumbnails != null) {
      prev['queueThumbnails'] = Map<String, dynamic>.from(queueThumbnails);
    }
    if (currentTrackUrl != null) prev['currentTrackUrl'] = currentTrackUrl;

    await box.put(id, prev);
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
    // For audio queue
    List<String>? queueUrls,
    Map<String, String>? queueTitles,
    Map<String, String>? queueThumbnails,
    String? currentTrackUrl,
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
        queueUrls: queueUrls,
        queueTitles: queueTitles,
        queueThumbnails: queueThumbnails,
        currentTrackUrl: currentTrackUrl,
      );
    } else {
      // pdf/epub/txt/cbz/etc can still use touch; _bestThumb will kick in
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

  // --- Readers ---------------------------------------------------------------

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
      immediate: true,
      deletedId: deletedId,
    );
  }

  List<Map<String, dynamic>> recent({int limit = 10}) {
    final box = _box;
    if (box == null || box.isEmpty) return [];

    final list =
        box.values
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
          );

    return list.take(limit).toList();
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
