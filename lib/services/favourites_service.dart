// lib/services/favourites_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../archive_api.dart';

part 'favourites_service.g.dart';

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
    id: json['id'] as String,
    title: json['title'] as String,
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

  late Box _box;

  Future<void> init() async {
    // Hive already initialised in main.dart → no redundant call
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FavoriteItemAdapter());
    }

    _box = await Hive.openBox(_boxName);
    await _migrateIfNeeded();

    // SAFE MIGRATION – never crash the app
    try {
      await _migrateOldFavorites();
    } catch (e, s) {
      debugPrint('Favorites migration failed (non-fatal): $e\n$s');
    }

    _notify();
  }

  // ------------------- THUMBNAILS -------------------
  Map<String, String> get _thumbMap {
    final raw = _box.get(_thumbsKey);
    if (raw is Map) return Map<String, String>.from(raw);
    return <String, String>{};
  }

  Future<void> _saveThumbMap(Map<String, String> map) async {
    await _box.put(_thumbsKey, map);
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

  // ------------------- FOLDER DATA -------------------
  Map<String, List<FavoriteItem>> get _data {
    final dynamic raw = _box.get('folders') ?? _box.get('data');
    if (raw == null) return <String, List<FavoriteItem>>{};

    if (raw is Map<String, List<FavoriteItem>>) return raw;

    if (raw is Map) {
      final result = <String, List<FavoriteItem>>{};
      raw.forEach((key, value) {
        final folder = key?.toString() ?? 'Favourites';
        final list = <FavoriteItem>[];

        if (value is List) {
          for (final e in value) {
            if (e is FavoriteItem) {
              list.add(e);
            } else if (e is Map) {
              try {
                list.add(FavoriteItem.fromJson(Map<String, dynamic>.from(e)));
              } catch (_) {
                list.add(
                  FavoriteItem(
                    id: (e['id'] ?? e['identifier'] ?? '').toString(),
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
                        (e['files'] as List?)
                            ?.map((f) => Map<String, String>.from(f as Map))
                            .toList(),
                  ),
                );
              }
            }
          }
        }
        result[folder] = list;
      });

      _box.put('folders', result);
      if (_box.containsKey('data')) _box.delete('data');
      return result;
    }

    return <String, List<FavoriteItem>>{};
  }

  Future<void> _save(Map<String, List<FavoriteItem>> data) async {
    await _box.put('folders', data);
    _notify();
  }

  Future<void> _migrateIfNeeded() async {
    final hasFolders = _box.containsKey('folders');
    final hasLegacy = _box.containsKey('data');

    if (!hasFolders && !hasLegacy) {
      await _box.put('folders', {'Favourites': <FavoriteItem>[]});
      return;
    }

    final normalized = _data;
    if (normalized.isEmpty) {
      await _box.put('folders', {'Favourites': <FavoriteItem>[]});
    }
  }

  // ------------------- SAFE MIGRATION -------------------
  Future<void> _migrateOldFavorites() async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool changed = false;

    for (final folder in data.keys) {
      final list = data[folder]!;
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        if (item.files == null) {
          try {
            final files = await ArchiveApi.fetchFilesForIdentifier(item.id);
            list[i] = item.copyWith(files: files);
            changed = true;
            debugPrint('Migrated files for ${item.id}');
          } catch (e) {
            debugPrint('Failed to migrate files for ${item.id}: $e');
            // keep entry – just no files
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
      (_data[folder] ?? const []).any((e) => e.id == id);

  List<String> foldersForItem(String id) {
    final res = <String>[];
    _data.forEach((f, list) {
      if (list.any((e) => e.id == id)) res.add(f);
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
    if (contains(trimmedFolder, id)) return;

    final item = FavoriteItem(
      id: id,
      title: title,
      url: url,
      thumb: thumb,
      author: author,
      mediatype: mediatype,
      formats: formats,
    );

    List<Map<String, String>> files = [];
    try {
      files = await ArchiveApi.fetchFilesForIdentifier(id);
      debugPrint('Fetched ${files.length} files for $id');
    } catch (e) {
      debugPrint('Failed to fetch files for $id: $e');
    }

    final finalItem = item.copyWith(files: files);
    await addToFolder(trimmedFolder, finalItem);
  }

  Future<void> addToFolder(String folder, FavoriteItem item) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    final list = List<FavoriteItem>.from(
      data.putIfAbsent(folder, () => <FavoriteItem>[]),
    );

    if (!list.any((e) => e.id == item.id)) {
      final latestThumb = getThumbForId(item.id) ?? item.thumb;
      final finalItem = item.copyWith(thumb: latestThumb);
      list.add(finalItem);
      data[folder] = list;
      await _save(data);
    }
  }

  Future<void> removeFromFolder(String folder, String id) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    final list = List<FavoriteItem>.from(data[folder] ?? const []);
    list.removeWhere((e) => e.id == id);
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

  // ------------------- PUBLIC HELPERS -------------------
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
    for (final list in _data.values) {
      for (final item in list) {
        if (item.id == id) {
          final latestThumb = getThumbForId(item.id);
          return latestThumb != null && latestThumb != item.thumb
              ? item.copyWith(thumb: latestThumb)
              : item;
        }
      }
    }
    return null;
  }

  bool containsInAnyFolder(String id) =>
      _data.values.any((list) => list.any((e) => e.id == id));

  Future<void> removeFromAllFolders(String id) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool removed = false;
    final folderNames = List<String>.from(data.keys);
    for (final folder in folderNames) {
      final list = List<FavoriteItem>.from(data[folder] ?? const []);
      final before = list.length;
      list.removeWhere((e) => e.id == id);
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
}
