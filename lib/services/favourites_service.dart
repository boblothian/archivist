// lib/services/favourites_service.dart
// PATCH: skip file fetch for collections during migration.
// ADD: audit helper to verify audio files saved as expected.
// PATCH 1: upsert behaviour in addToFolder()
// PATCH 2: optional explicit updater for convenience

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../archive_api.dart';
import '../utils/archive_helpers.dart';

part 'favourites_service.g.dart';

String sanitizeArchiveId(String id) {
  var s = id.trim();
  if (s.startsWith('metadata/')) s = s.substring('metadata/'.length);
  if (s.startsWith('details/')) s = s.substring('details/'.length);
  return s;
}

@HiveType(typeId: 0)
class FavoriteItem extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String? url;
  @HiveField(3)
  final String? thumb;
  @HiveField(4)
  final String? author;
  @HiveField(5)
  final String? mediatype;
  @HiveField(6)
  final List<String> formats;
  @HiveField(7)
  final List<Map<String, String>>? files;

  FavoriteItem({
    required this.id,
    required this.title,
    this.url,
    this.thumb,
    this.author,
    this.mediatype,
    this.formats = const [],
    this.files,
  });

  FavoriteItem copyWith({
    String? thumb,
    String? mediatype,
    List<String>? formats,
    List<Map<String, String>>? files,
  }) => FavoriteItem(
    id: id,
    title: title,
    url: url,
    thumb: thumb ?? this.thumb,
    author: author,
    mediatype: mediatype ?? this.mediatype,
    formats: formats ?? this.formats,
    files: files ?? this.files,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'thumb': thumb,
    'author': author,
    'mediatype': mediatype,
    'formats': formats,
    'files': files,
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
    id: sanitizeArchiveId((json['id'] ?? '').toString()),
    title: (json['title'] ?? '').toString(),
    url: json['url'] as String?,
    thumb: json['thumb'] as String?,
    author: json['author'] as String?,
    mediatype: json['mediatype'] as String?,
    formats: (json['formats'] as List?)?.cast<String>() ?? [],
    files:
        (json['files'] as List?)
            ?.map((e) => Map<String, String>.from(e as Map))
            .toList(),
  );

  @override
  String toString() =>
      'FavoriteItem(id: $id, title: $title, files: ${files?.length ?? 0})';
}

class FavoritesService {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  final version = ValueNotifier<int>(0);
  void _notify() => version.value++;

  static const _boxName = 'favorites_v2';
  static const _thumbsKey = 'thumbs';

  Box<dynamic>? _box;

  List<Map<String, String>> _normalizeFiles(
    List<Map<String, String>> files, {
    String? identifier,
  }) {
    String extractName(Map<String, String> m) {
      String name = (m['name'] ?? '').toString();
      if (name.trim().isEmpty) {
        name = (m['filename'] ?? m['pretty'] ?? '').toString();
      }
      if (name.trim().isEmpty) {
        final url = (m['url'] ?? '').toString();
        if (url.isNotEmpty) {
          try {
            name = Uri.decodeComponent(Uri.parse(url).pathSegments.last);
          } catch (_) {}
        }
      }
      return name.trim();
    }

    final out = <Map<String, String>>[];
    for (final f in files) {
      final m = Map<String, String>.from(f);
      final name = extractName(m);
      if (name.isEmpty) continue; // drop unusable entries
      m['name'] = name; // enforce presence for downstream extension checks
      out.add(m);
    }
    return out;
  }

  Box<dynamic> get box {
    final b = _box;
    if (b == null || !b.isOpen) {
      throw StateError(
        'FavoritesService not initialized. Call init() and await it first.',
      );
    }
    return b;
  }

  late final Future<void> ready = _init();
  Future<void> init() => ready;

  Future<void> _init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FavoriteItemAdapter());
    }
    _box =
        Hive.isBoxOpen(_boxName)
            ? Hive.box<dynamic>(_boxName)
            : await Hive.openBox<dynamic>(_boxName);

    await _migrateIfNeeded();

    try {
      await _migrateOldFavorites();
    } catch (e, s) {
      debugPrint('Favorites migration failed (non-fatal): $e\n$s');
    }

    _notify();
  }

  Map<String, String> get _thumbMap {
    final raw = box.get(_thumbsKey);
    if (raw is Map) return Map<String, String>.from(raw);
    return <String, String>{};
  }

  Future<void> _saveThumbMap(Map<String, String> map) async {
    await box.put(_thumbsKey, map);
  }

  String? getThumbForId(String id) => _thumbMap[id];

  Future<void> updateThumbForId(String id, String newThumb) async {
    final thumbs = Map<String, String>.from(_thumbMap);
    if (thumbs[id] == newThumb) return;
    thumbs[id] = newThumb;
    await _saveThumbMap(thumbs);

    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool updated = false;
    data.forEach((folder, list) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == id && list[i].thumb != newThumb) {
          list[i] = list[i].copyWith(thumb: newThumb);
          updated = true;
        }
      }
    });

    if (updated) await _save(data);
    _notify();
  }

  Map<String, String> get thumbOverrides =>
      Map<String, String>.unmodifiable(_thumbMap);

  Future<int> mergeThumbOverrides(Map<String, String> incoming) async {
    if (incoming.isEmpty) return 0;
    final current = Map<String, String>.from(_thumbMap);
    int changed = 0;

    incoming.forEach((id, t) {
      final key = sanitizeArchiveId(id);
      final val = t.trim();
      if (key.isEmpty || val.isEmpty) return;
      if (current[key] != val) {
        current[key] = val;
        changed++;
      }
    });

    if (changed > 0) {
      await _saveThumbMap(current);
      _notify();
    }
    return changed;
  }

  Map<String, List<FavoriteItem>> get _data {
    final dynamic raw = box.get('folders') ?? box.get('data');
    if (raw == null) return <String, List<FavoriteItem>>{};

    if (raw is Map<String, List<FavoriteItem>>) {
      final fixed = <String, List<FavoriteItem>>{};
      raw.forEach((folder, list) {
        final out = <FavoriteItem>[];
        for (final e in list) {
          final idClean = sanitizeArchiveId(e.id);
          final normalized =
              e.files != null
                  ? e.copyWith(
                    files: _normalizeFiles(e.files!, identifier: idClean),
                  )
                  : e;

          if (idClean == e.id) {
            out.add(normalized);
          } else {
            out.add(
              FavoriteItem(
                id: idClean,
                title: e.title,
                url: e.url,
                thumb: e.thumb,
                author: e.author,
                mediatype: e.mediatype,
                formats: e.formats,
                files: normalized.files,
              ),
            );
          }
        }
        fixed[folder] = out;
      });
      return fixed;
    }

    if (raw is Map) {
      final result = <String, List<FavoriteItem>>{};
      raw.forEach((key, value) {
        final folder = key?.toString() ?? 'Favourites';
        final list = <FavoriteItem>[];

        if (value is List) {
          for (final e in value) {
            if (e is FavoriteItem) {
              final idClean = sanitizeArchiveId(e.id);
              final normalized =
                  e.files != null
                      ? e.copyWith(
                        files: _normalizeFiles(e.files!, identifier: idClean),
                      )
                      : e;
              list.add(
                idClean == e.id
                    ? normalized
                    : FavoriteItem(
                      id: idClean,
                      title: e.title,
                      url: e.url,
                      thumb: e.thumb,
                      author: e.author,
                      mediatype: e.mediatype,
                      formats: e.formats,
                      files: normalized.files,
                    ),
              );
            } else if (e is Map) {
              try {
                final parsed = FavoriteItem.fromJson(
                  Map<String, dynamic>.from(e),
                );
                final idClean = sanitizeArchiveId(parsed.id);
                final normalized =
                    parsed.files != null
                        ? parsed.copyWith(
                          files: _normalizeFiles(
                            parsed.files!,
                            identifier: idClean,
                          ),
                        )
                        : parsed;
                list.add(
                  idClean == parsed.id
                      ? normalized
                      : FavoriteItem(
                        id: idClean,
                        title: normalized.title,
                        url: normalized.url,
                        thumb: normalized.thumb,
                        author: normalized.author,
                        mediatype: normalized.mediatype,
                        formats: normalized.formats,
                        files: normalized.files,
                      ),
                );
              } catch (_) {
                final idStr = sanitizeArchiveId(
                  (e['id'] ?? e['identifier'] ?? '').toString(),
                );
                final rawFiles =
                    (e['files'] as List?)
                        ?.map((f) => Map<String, String>.from(f as Map))
                        .toList();
                list.add(
                  FavoriteItem(
                    id: idStr,
                    title: (e['title'] ?? '').toString(),
                    url: (e['url'] as String?) ?? '',
                    thumb:
                        (e['thumb'] as String?) ??
                        (e['thumbnail'] as String?) ??
                        '',
                    author: e['author'] as String?,
                    mediatype: e['mediatype'] as String?,
                    formats: (e['formats'] as List?)?.cast<String>() ?? [],
                    files:
                        rawFiles != null
                            ? _normalizeFiles(rawFiles, identifier: idStr)
                            : null,
                  ),
                );
              }
            }
          }
        }
        result[folder] = list;
      });

      box.put('folders', result);
      if (box.containsKey('data')) box.delete('data');
      return result;
    }

    return <String, List<FavoriteItem>>{};
  }

  Future<void> _save(Map<String, List<FavoriteItem>> data) async {
    final fixed = <String, List<FavoriteItem>>{};
    data.forEach((folder, list) {
      fixed[folder] =
          list
              .map(
                (e) =>
                    e.id == sanitizeArchiveId(e.id)
                        ? e
                        : FavoriteItem(
                          id: sanitizeArchiveId(e.id),
                          title: e.title,
                          url: e.url,
                          thumb: e.thumb,
                          author: e.author,
                          mediatype: e.mediatype,
                          formats: e.formats,
                          files: e.files,
                        ),
              )
              .toList();
    });
    await box.put('folders', fixed);
    _notify();
  }

  Future<void> _migrateIfNeeded() async {
    final hasFolders = box.containsKey('folders');
    final hasLegacy = box.containsKey('data');

    if (!hasFolders && !hasLegacy) {
      await box.put('folders', {'Favourites': <FavoriteItem>[]});
      return;
    }

    final normalized = _data; // triggers normalization + id sanitization
    if (normalized.isEmpty) {
      await box.put('folders', {'Favourites': <FavoriteItem>[]});
    } else {
      await box.put('folders', normalized);
    }
  }

  // ------------------- SAFE MIGRATION (patched) -------------------
  Future<void> _migrateOldFavorites() async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool changed = false;

    for (final folder in data.keys) {
      final list = data[folder]!;
      for (int i = 0; i < list.length; i++) {
        var item = list[i];
        final cleanId = sanitizeArchiveId(item.id);

        if (cleanId != item.id) {
          item = FavoriteItem(
            id: cleanId,
            title: item.title,
            url: item.url,
            thumb: item.thumb,
            author: item.author,
            mediatype: item.mediatype,
            formats: item.formats,
            files: item.files,
          );
          list[i] = item;
          changed = true;
        }

        String mt = (item.mediatype ?? '').toLowerCase();

        if (mt.isEmpty) {
          try {
            final meta = await ArchiveApi.getMetadata(cleanId);
            final raw = Map<String, dynamic>.from(meta['metadata'] ?? {});
            final resolved =
                (raw['mediatype'] ?? '').toString().trim().toLowerCase();
            if (resolved.isNotEmpty) {
              list[i] = list[i].copyWith(mediatype: resolved);
              changed = true;
              mt = resolved;
            }
          } catch (e) {
            debugPrint('Failed to resolve mt for $cleanId: $e');
          }
        }

        // Skip fetching for collections/unknown; keep behavior aligned with addFavoriteWithFiles.
        final isCollection = mt == 'collection';
        final isUnknown = mt.isEmpty || mt == 'unknown';

        if (item.files == null && !isCollection && !isUnknown) {
          try {
            var files = await ArchiveApi.fetchFilesForIdentifier(cleanId);
            files = _normalizeFiles(
              files.map((e) => Map<String, String>.from(e)).toList(),
              identifier: cleanId,
            );
            list[i] = item.copyWith(files: files);
            changed = true;
            debugPrint('Migrated files for $cleanId');
          } catch (e) {
            debugPrint('Failed to migrate files for $cleanId: $e');
          }
        }
      }
    }

    if (changed) await _save(data);
  }

  // ------------------- FOLDER OPS -------------------
  List<String> folders() {
    final names = _data.keys.toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  bool folderExists(String name) => _data.containsKey(name);

  Future<void> createFolder(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final data = Map<String, List<FavoriteItem>>.from(_data);
    data.putIfAbsent(n, () => <FavoriteItem>[]);
    await _save(data);
  }

  Future<void> renameFolder(String oldName, String newName) async {
    final n = newName.trim();
    if (n.isEmpty || n == oldName) return;
    final data = Map<String, List<FavoriteItem>>.from(_data);
    if (!data.containsKey(oldName) || data.containsKey(n)) return;
    data[n] = data.remove(oldName)!;
    await _save(data);
  }

  Future<void> deleteFolder(String name) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    if (data.remove(name) != null) await _save(data);
  }

  // ------------------- ITEM OPS -------------------
  List<FavoriteItem> itemsIn(String folder) {
    final list = _data[folder] ?? const <FavoriteItem>[];
    return list.map((item) {
      final latestThumb = getThumbForId(item.id);
      return latestThumb != null && latestThumb != item.thumb
          ? item.copyWith(thumb: latestThumb)
          : item;
    }).toList();
  }

  bool contains(String folder, String id) =>
      (_data[folder] ?? const []).any((e) => e.id == sanitizeArchiveId(id));

  List<String> foldersForItem(String id) {
    final target = sanitizeArchiveId(id);
    final res = <String>[];
    _data.forEach((f, list) {
      if (list.any((e) => e.id == target)) res.add(f);
    });
    res.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return res;
  }

  Future<void> addFavoriteWithFiles({
    required String folder,
    required String id,
    required String title,
    String? url,
    String? thumb,
    String? author,
    String? mediatype,
    List<String> formats = const [],
  }) async {
    final trimmedFolder = folder.trim();
    final cleanId = sanitizeArchiveId(id);
    if (contains(trimmedFolder, cleanId)) return;

    String? resolvedMediatype = mediatype?.toLowerCase();
    String? resolvedThumb = thumb;
    List<String> resolvedFormats = formats;

    if (resolvedMediatype == null) {
      try {
        final meta = await ArchiveApi.getMetadata(cleanId);
        final md = (meta['metadata'] as Map?) ?? {};
        resolvedMediatype = (md['mediatype'] as String?)?.toLowerCase();
        resolvedThumb ??= archiveThumbUrl(cleanId);
      } catch (e) {
        debugPrint('Failed to resolve mediatype for $cleanId: $e');
        resolvedMediatype = 'unknown';
      }
    }

    final item = FavoriteItem(
      id: cleanId,
      title: title,
      url: url ?? 'https://archive.org/details/$cleanId',
      thumb: resolvedThumb,
      author: author,
      mediatype: resolvedMediatype,
      formats: resolvedFormats,
    );

    if (resolvedMediatype == 'collection' || resolvedMediatype == 'unknown') {
      await addToFolder(trimmedFolder, item);
      return;
    }

    List<Map<String, String>> files = [];
    try {
      files = await ArchiveApi.fetchFilesForIdentifier(cleanId);
      files = _normalizeFiles(files, identifier: cleanId);
    } catch (e) {
      debugPrint('Failed to fetch files for $cleanId: $e');
    }

    final finalItem = item.copyWith(files: files);
    await addToFolder(trimmedFolder, finalItem);
  }

  // --- PATCH 1: upsert behaviour in addToFolder() ---
  Future<void> addToFolder(String folder, FavoriteItem item) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    final list = List<FavoriteItem>.from(
      data.putIfAbsent(folder, () => <FavoriteItem>[]),
    );
    final cleanId = sanitizeArchiveId(item.id);
    final latestThumb = getThumbForId(cleanId) ?? item.thumb;
    final normalizedFiles =
        item.files != null
            ? _normalizeFiles(item.files!, identifier: cleanId)
            : null;
    final idx = list.indexWhere((e) => e.id == cleanId);
    if (idx >= 0) {
      // merge into existing
      final cur = list[idx];
      final merged = FavoriteItem(
        id: cur.id,
        title: cur.title.isNotEmpty ? cur.title : item.title,
        url: (item.url?.trim().isNotEmpty == true) ? item.url : cur.url,
        thumb: latestThumb ?? cur.thumb,
        author: item.author ?? cur.author,
        // prefer incoming mediatype if present
        mediatype:
            (item.mediatype?.trim().isNotEmpty == true)
                ? item.mediatype
                : cur.mediatype,
        // prefer non-empty incoming formats; else keep existing
        formats: (item.formats.isNotEmpty) ? item.formats : cur.formats,
        // prefer incoming files when provided; else keep existing
        files: normalizedFiles ?? cur.files,
      );
      list[idx] = merged;
    } else {
      // insert new
      final finalItem = FavoriteItem(
        id: cleanId,
        title: item.title,
        url: item.url,
        thumb: latestThumb,
        author: item.author,
        mediatype: item.mediatype,
        formats: item.formats,
        files: normalizedFiles,
      );
      list.add(finalItem);
    }
    data[folder] = list;
    await _save(data);
  }

  // --- PATCH 2: optional explicit updater for convenience ---
  Future<void> updateFavorite({
    required String id,
    String? folder, // if null, update in all folders containing the item
    String? title,
    String? url,
    String? thumb,
    String? author,
    String? mediatype,
    List<String>? formats,
    List<Map<String, String>>? files,
  }) async {
    final cleanId = sanitizeArchiveId(id);
    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool changed = false;
    final foldersToTouch = folder == null ? data.keys.toList() : [folder];
    for (final f in foldersToTouch) {
      final list = List<FavoriteItem>.from(data[f] ?? const <FavoriteItem>[]);
      for (int i = 0; i < list.length; i++) {
        if (list[i].id != cleanId) continue;
        final normalizedFiles =
            files != null ? _normalizeFiles(files, identifier: cleanId) : null;
        list[i] = FavoriteItem(
          id: list[i].id,
          title: title ?? list[i].title,
          url: url ?? list[i].url,
          thumb: thumb ?? list[i].thumb,
          author: author ?? list[i].author,
          mediatype: mediatype ?? list[i].mediatype,
          formats: formats ?? list[i].formats,
          files: normalizedFiles ?? list[i].files,
        );
        data[f] = list;
        changed = true;
      }
    }
    if (changed) await _save(data);
  }

  Future<void> removeFromFolder(String folder, String id) async {
    final target = sanitizeArchiveId(id);
    final data = Map<String, List<FavoriteItem>>.from(_data);
    final list = List<FavoriteItem>.from(data[folder] ?? const []);
    list.removeWhere((e) => e.id == target);
    if (list.isEmpty && folder != 'Favourites') {
      data.remove(folder);
    } else {
      data[folder] = list;
    }
    await _save(data);
  }

  Future<bool> toggleInFolder(String folder, FavoriteItem item) async {
    if (contains(folder, item.id)) {
      await removeFromFolder(folder, item.id);
      return false;
    }
    await addToFolder(folder, item);
    return true;
  }

  List<FavoriteItem> get allItems {
    final seen = <String, FavoriteItem>{};
    for (final items in _data.values) {
      for (final item in items) {
        final latestThumb = getThumbForId(item.id);
        final updated =
            latestThumb != null && latestThumb != item.thumb
                ? item.copyWith(thumb: latestThumb)
                : item;
        seen[updated.id] = updated;
      }
    }
    return seen.values.toList(growable: false);
  }

  FavoriteItem? byId(String id) {
    final target = sanitizeArchiveId(id);
    for (final list in _data.values) {
      for (final item in list) {
        if (item.id == target) {
          final latestThumb = getThumbForId(item.id);
          return latestThumb != null && latestThumb != item.thumb
              ? item.copyWith(thumb: latestThumb)
              : item;
        }
      }
    }
    return null;
  }

  bool containsInAnyFolder(String id) {
    final target = sanitizeArchiveId(id);
    return _data.values.any((list) => list.any((e) => e.id == target));
  }

  Future<void> removeFromAllFolders(String id) async {
    final target = sanitizeArchiveId(id);
    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool removed = false;
    final folderNames = List<String>.from(data.keys);
    for (final folder in folderNames) {
      final list = List<FavoriteItem>.from(data[folder] ?? const []);
      final before = list.length;
      list.removeWhere((e) => e.id == target);
      if (list.length < before) {
        removed = true;
        if (list.isEmpty && folder != 'Favourites') {
          data.remove(folder);
        } else {
          data[folder] = list;
        }
      }
    }
    if (removed) await _save(data);
  }

  Future<void> remove(String id, {String? fromFolder}) async {
    final folder = fromFolder?.trim();
    if (folder == null || folder.isEmpty || folder == 'All') {
      await removeFromAllFolders(id);
    } else {
      await removeFromFolder(folder, id);
    }
  }

  // ------------------- AUDIT: verify audio files saved -------------------
  /// Returns a compact report and optional detailed problems list.
  Future<({String summary, List<String> problems})> auditAudioFiles() async {
    final data = _data;
    int audioCount = 0;
    int audioWithFiles = 0;
    int audioWithoutFiles = 0;
    int collectionCount = 0;

    final problems = <String>[];

    for (final entry in data.entries) {
      final folder = entry.key;
      for (final it in entry.value) {
        final mt = (it.mediatype ?? '').toLowerCase();
        if (mt == 'collection') {
          collectionCount++;
          if (it.files != null && it.files!.isNotEmpty) {
            problems.add('[collection-has-files] ${it.id} ($folder)');
          }
          continue;
        }
        final isAudio = mt == 'audio' || mt == 'etree';
        if (isAudio) {
          audioCount++;
          final hasFiles = (it.files != null && it.files!.isNotEmpty);
          if (hasFiles) {
            audioWithFiles++;
          } else {
            audioWithoutFiles++;
            problems.add('[audio-missing-files] ${it.id} ($folder)');
          }
        }
      }
    }

    final summary =
        'Audio items: $audioCount | with files: $audioWithFiles | missing files: $audioWithoutFiles | collections: $collectionCount';
    return (summary: summary, problems: problems);
  }
}
