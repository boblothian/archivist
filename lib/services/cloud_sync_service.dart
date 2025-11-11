// lib/services/cloud_sync_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'favourites_service.dart';
import 'recent_progress_service.dart';

/// Syncs local Hive-backed data (favorites, recent, thumbs) with Firestore.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  String? _uid;
  DocumentReference<Map<String, dynamic>>? _userDoc;

  Timer? _debounce;
  bool _pushing = false;
  bool _pulled = false;

  VoidCallback? _favListener;
  VoidCallback? _recentListener;

  Future<void> start({required String uid}) async {
    if (_uid == uid && _userDoc != null) return;
    _uid = uid;
    _userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

    await _userDoc!.set({
      '_createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Await init to prevent race
    await FavoritesService.instance.init();
    await RecentProgressService.instance.init();

    // iOS: Clear Firestore cache to prevent ghost restores
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await FirebaseFirestore.instance.clearPersistence();
        debugPrint('iOS Firestore cache cleared');
      } catch (e) {
        debugPrint('Failed to clear persistence: $e');
      }
    }

    await _pullOnce();

    _favListener ??= schedulePush;
    _recentListener ??= schedulePush;

    FavoritesService.instance.version.addListener(_favListener!);
    RecentProgressService.instance.version.addListener(_recentListener!);

    schedulePush();
  }

  Future<void> stop() async {
    _favListener = null;
    _recentListener = null;
    _debounce?.cancel();
    _debounce = null;
  }

  void schedulePush({bool immediate = false, String? deletedId}) {
    _debounce?.cancel();
    final delay = immediate ? Duration.zero : const Duration(milliseconds: 100);
    _debounce = Timer(delay, () => _pushSafely(deletedId: deletedId));
  }

  // ---------------- Pull (one-time merge) ----------------
  Future<void> _pullOnce() async {
    if (_pulled || _userDoc == null) return;
    final snap = await _userDoc!.get();
    final data = snap.data();
    _pulled = true;
    if (data == null) return;

    // 1) Favorites folders
    final favFolders =
        (data['favoritesFolders'] as Map?)?.cast<String, dynamic>() ?? {};
    if (favFolders.isNotEmpty) {
      final svc = FavoritesService.instance;
      for (final entry in favFolders.entries) {
        final folder = entry.key;
        final list = (entry.value as List?)?.cast<dynamic>() ?? const [];
        final localIds = svc.itemsIn(folder).map((e) => e.id).toSet();

        for (final raw in list) {
          if (raw is! Map) continue;
          try {
            final remote = FavoriteItem.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (!localIds.contains(remote.id)) {
              await svc.addToFolder(folder, remote);
              localIds.add(remote.id);
            } else {
              final local = svc
                  .itemsIn(folder)
                  .firstWhere((e) => e.id == remote.id);
              final localHasFiles = (local.files?.isNotEmpty ?? false);
              final remoteHasFiles = (remote.files?.isNotEmpty ?? false);
              if (!localHasFiles && remoteHasFiles) {
                await svc.removeFromFolder(folder, remote.id);
                await svc.addToFolder(
                  folder,
                  local.copyWith(
                    thumb: remote.thumb ?? local.thumb,
                    mediatype: remote.mediatype ?? local.mediatype,
                    formats:
                        remote.formats.isNotEmpty
                            ? remote.formats
                            : local.formats,
                    files: remote.files ?? local.files,
                  ),
                );
              }
            }
          } catch (_) {}
        }
      }
    }

    // 2) Thumbs
    final remoteThumbs =
        (data['thumbs'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        {};
    if (remoteThumbs.isNotEmpty) {
      await FavoritesService.instance.mergeThumbOverrides(remoteThumbs);
    }

    // 3) Recent progress — timestamp merge
    final recentMap =
        (data['recentProgress'] as Map?)?.cast<String, dynamic>() ?? {};
    if (recentMap.isNotEmpty) {
      final rsvc = RecentProgressService.instance;
      for (final e in recentMap.entries) {
        final id = e.key;
        final remote = Map<String, dynamic>.from(e.value as Map);
        final local = rsvc.getById(id);
        final rTime = (remote['lastOpenedAt'] as int?) ?? 0;
        final lTime = (local?['lastOpenedAt'] as int?) ?? 0;

        // Skip if local exists and is newer or equal
        if (local != null && rTime <= lTime) continue;

        final kind = (remote['kind'] as String?)?.toLowerCase() ?? '';
        final title = (remote['title'] as String?) ?? id;
        final thumb = remote['thumb'] as String?;
        final fileUrl = remote['fileUrl'] as String?;
        final fileName = remote['fileName'] as String?;

        if (kind == 'video') {
          final percent = (remote['percent'] as num?)?.toDouble() ?? 0.0;
          final positionMs = remote['positionMs'] as int?;
          final durationMs = remote['durationMs'] as int?;
          await rsvc.updateVideo(
            id: id,
            title: title,
            thumb: thumb,
            percent: percent,
            fileUrl: fileUrl ?? '',
            fileName: fileName ?? '',
            positionMs: positionMs,
            durationMs: durationMs,
          );
        } else if (kind == 'audio') {
          final percent = (remote['percent'] as num?)?.toDouble() ?? 0.0;
          final positionMs = remote['positionMs'] as int?;
          final durationMs = remote['durationMs'] as int?;
          await rsvc.updateAudio(
            id: id,
            title: title,
            thumb: thumb,
            fileUrl: fileUrl ?? '',
            fileName: fileName ?? '',
            percent: percent,
            positionMs: positionMs,
            durationMs: durationMs,
          );
        } else if (kind == 'epub') {
          await rsvc.updateEpub(
            id: id,
            title: title,
            thumb: thumb,
            page: (remote['page'] as int?) ?? 0,
            total: (remote['total'] as int?) ?? 0,
            percent: (remote['percent'] as num?)?.toDouble() ?? 0.0,
            cfi: (remote['cfi'] as String?) ?? '',
            fileUrl: fileUrl,
            fileName: fileName,
          );
        } else if (['pdf', 'cbz', 'cbr', 'txt'].contains(kind)) {
          await rsvc.updatePdf(
            id: id,
            title: title,
            thumb: thumb,
            page: (remote['page'] as int?) ?? 0,
            total: (remote['total'] as int?) ?? 0,
            fileUrl: fileUrl,
            fileName: fileName,
          );
        }
      }
    }
  }

  // ---------------- Push (debounced) ----------------
  Future<void> _pushSafely({String? deletedId}) async {
    if (_pushing || _userDoc == null) return;
    _pushing = true;
    try {
      final favPayload = <String, List<Map<String, dynamic>>>{};
      final fsvc = FavoritesService.instance;
      for (final folder in fsvc.folders()) {
        favPayload[folder] = fsvc
            .itemsIn(folder)
            .map((e) => e.toJson())
            .toList(growable: false);
      }

      final thumbsPayload = fsvc.thumbOverrides;

      final recentList = RecentProgressService.instance.recent(limit: 9999);
      final recentPayload = <String, Map<String, dynamic>>{
        for (final e in recentList)
          if ((e['id'] as String?)?.isNotEmpty == true) e['id'] as String: e,
      };

      await _userDoc!.set({
        'favoritesFolders': favPayload,
        'thumbs': thumbsPayload,
        'recentProgress': recentPayload,
        '_updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Explicit delete for safety
      if (deletedId != null) {
        await _userDoc!.update({
          'recentProgress.$deletedId': FieldValue.delete(),
        });
      }
    } catch (e, s) {
      debugPrint('CloudSync push failed: $e\n$s');
    } finally {
      _pushing = false;
    }
  }
}
