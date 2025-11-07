// lib/services/cloud_sync_service.dart  (FULL FILE)
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

    // Services ready (safe if already initialized)
    unawaited(FavoritesService.instance.init());
    unawaited(RecentProgressService.instance.init());

    await _pullOnce();

    _favListener ??= _schedulePush;
    _recentListener ??= _schedulePush;

    FavoritesService.instance.version.addListener(_favListener!);
    RecentProgressService.instance.version.addListener(_recentListener!);

    _schedulePush();
  }

  Future<void> stop() async {
    if (_favListener != null) {
      FavoritesService.instance.version.removeListener(_favListener!);
      _favListener = null;
    }
    if (_recentListener != null) {
      RecentProgressService.instance.version.removeListener(_recentListener!);
      _recentListener = null;
    }
    _debounce?.cancel();
    _debounce = null;
  }

  void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _pushSafely);
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
          } catch (_) {
            /* ignore malformed rows */
          }
        }
      }
    }

    // 2) Thumbs (overrides)
    final remoteThumbs =
        (data['thumbs'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        {};
    if (remoteThumbs.isNotEmpty) {
      await FavoritesService.instance.mergeThumbOverrides(remoteThumbs);
    }

    // 3) Recent progress
    final recentMap =
        (data['recentProgress'] as Map?)?.cast<String, dynamic>() ?? {};
    if (recentMap.isNotEmpty) {
      final rsvc = RecentProgressService.instance;
      for (final e in recentMap.entries) {
        final id = e.key;
        final remote = Map<String, dynamic>.from(e.value as Map);
        final local = rsvc.getById(id);
        final r = (remote['lastOpenedAt'] as int?) ?? 0;
        final l = (local?['lastOpenedAt'] as int?) ?? 0;
        if (r <= l) continue;

        final kind = (remote['kind'] as String?) ?? 'pdf';
        final title = (remote['title'] as String?) ?? id;
        final thumb = remote['thumb'] as String?;
        final fileUrl = remote['fileUrl'] as String?;
        final fileName = remote['fileName'] as String?;

        if (kind == 'video') {
          final percent = (remote['percent'] as num?)?.toDouble() ?? 0.0;
          await rsvc.updateVideo(
            id: id,
            title: title,
            thumb: thumb,
            percent: percent,
            fileUrl: fileUrl ?? '',
            fileName: fileName ?? '',
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
        } else {
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
  Future<void> _pushSafely() async {
    if (_pushing || _userDoc == null) return;
    _pushing = true;
    try {
      // Favorites payload
      final favPayload = <String, List<Map<String, dynamic>>>{};
      final fsvc = FavoritesService.instance;
      for (final folder in fsvc.folders()) {
        favPayload[folder] = fsvc
            .itemsIn(folder)
            .map((e) => e.toJson())
            .toList(growable: false);
      }

      // Thumbs payload
      final thumbsPayload = fsvc.thumbOverrides;

      // Recent payload
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
    } catch (e, s) {
      debugPrint('CloudSync push failed: $e\n$s');
    } finally {
      _pushing = false;
    }
  }
}
