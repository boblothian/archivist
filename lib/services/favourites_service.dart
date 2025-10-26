// lib/services/favourites_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  FavoriteItem({
    required this.id,
    required this.title,
    this.url,
    this.thumb,
    this.author,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'thumb': thumb,
    'author': author,
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
    id: json['id'] as String,
    title: json['title'] as String,
    url: json['url'] as String?,
    thumb: json['thumb'] as String?,
    author: json['author'] as String?,
  );

  @override
  String toString() => 'FavoriteItem(id: $id, title: $title)';
}

class FavoritesService {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  final version = ValueNotifier<int>(0);
  void _notify() => version.value++;

  static const _boxName = 'favorites_v2';

  // Option A: untyped box so we can migrate legacy shapes safely.
  late Box _box;

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FavoriteItemAdapter());
    }

    _box = await Hive.openBox(_boxName);

    // One-time migration + ensure a default folder exists.
    await _migrateIfNeeded();

    _notify();
  }

  /// Normalized read of the folders map from Hive.
  /// Always returns a Map<String, List<FavoriteItem>> in canonical shape.
  Map<String, List<FavoriteItem>> get _data {
    // Prefer 'folders'; fall back to legacy key 'data' if present.
    final dynamic raw = _box.get('folders') ?? _box.get('data');

    // Nothing saved yet.
    if (raw == null) {
      return <String, List<FavoriteItem>>{};
    }

    // Already the correct typed structure.
    if (raw is Map<String, List<FavoriteItem>>) {
      return raw;
    }

    // Legacy / loosely typed map -> normalize it.
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
                list.add(
                  FavoriteItem.fromJson(Map<String, dynamic>.from(e as Map)),
                );
              } catch (_) {
                // Last-resort manual mapping
                list.add(
                  FavoriteItem(
                    id: (e['id'] ?? e['identifier'] ?? '').toString(),
                    title: (e['title'] ?? '').toString(),
                    url: (e['url'] as String?) ?? '',
                    thumb:
                        (e['thumb'] as String?) ??
                        (e['thumbnail'] as String?) ??
                        '',
                    author: (e['author'] as String?),
                  ),
                );
              }
            } else {
              // Unknown element type -> ignore
            }
          }
        }

        result[folder] = list;
      });

      // Persist back in canonical format under the correct key.
      _box.put('folders', result);
      // Remove legacy key if it exists.
      if (_box.containsKey('data')) {
        _box.delete('data');
      }
      return result;
    }

    // Fallback empty.
    return <String, List<FavoriteItem>>{};
  }

  /// Persist a full folders map back to Hive and notify listeners.
  Future<void> _save(Map<String, List<FavoriteItem>> data) async {
    await _box.put('folders', data);
    _notify();
  }

  /// Ensure we have a normalized structure and at least one default folder.
  Future<void> _migrateIfNeeded() async {
    final hasFolders = _box.containsKey('folders');
    final hasLegacy = _box.containsKey('data');

    if (!hasFolders && !hasLegacy) {
      await _box.put('folders', {'Favourites': <FavoriteItem>[]});
      return;
    }

    // Reading via _data will normalize and write back if needed.
    final normalized = _data;

    if (normalized.isEmpty) {
      // Guarantee at least the default folder exists.
      await _box.put('folders', {'Favourites': <FavoriteItem>[]});
    }
  }

  // -----------------------
  // Folder operations
  // -----------------------

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
    if (data.remove(name) != null) {
      await _save(data);
    }
  }

  // -----------------------
  // Item operations
  // -----------------------

  List<FavoriteItem> itemsIn(String folder) =>
      List.unmodifiable(_data[folder] ?? const []);

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

  Future<void> addToFolder(String folder, FavoriteItem item) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    final list = List<FavoriteItem>.from(
      data.putIfAbsent(folder, () => <FavoriteItem>[]),
    );

    if (!list.any((e) => e.id == item.id)) {
      list.add(item);
      data[folder] = list;
      await _save(data);
    }
  }

  Future<void> removeFromFolder(String folder, String id) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    final list = List<FavoriteItem>.from(
      data[folder] ?? const <FavoriteItem>[],
    );

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

  // -----------------------
  // Public helpers
  // -----------------------

  List<FavoriteItem> get allItems {
    final seen = <String, FavoriteItem>{};
    for (final items in _data.values) {
      for (final item in items) {
        seen[item.id] = item;
      }
    }
    return seen.values.toList(growable: false);
  }

  bool containsInAnyFolder(String id) =>
      _data.values.any((list) => list.any((e) => e.id == id));

  Future<void> removeFromAllFolders(String id) async {
    final data = Map<String, List<FavoriteItem>>.from(_data);
    bool removed = false;

    data.forEach((folder, list) {
      final newList = List<FavoriteItem>.from(list);
      final before = newList.length;
      newList.removeWhere((e) => e.id == id);
      if (newList.length < before) {
        removed = true;
        if (newList.isEmpty && folder != 'Favourites') {
          // delete empty non-default folder
          data.remove(folder);
        } else {
          data[folder] = newList;
        }
      }
    });

    if (removed) {
      await _save(data);
    }
  }
}
