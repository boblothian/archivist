// lib/services/favourites_service.dart
import 'dart:convert';

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
  late Box<Map<String, List<FavoriteItem>>> _box;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(FavoriteItemAdapter());

    _box = await Hive.openBox<Map<String, List<FavoriteItem>>>(_boxName);

    if (_box.isEmpty) {
      await _box.put('folders', {'Favourites': <FavoriteItem>[]});
    }

    _notify();
  }

  Map<String, List<FavoriteItem>> get _data {
    return _box.get('folders', defaultValue: <String, List<FavoriteItem>>{})!;
  }

  Future<void> _persist() async {
    await _box.put('folders', _data);
    _notify();
  }

  // Folders
  List<String> folders() {
    final list = _data.keys.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  bool folderExists(String name) => _data.containsKey(name);

  Future<void> createFolder(String name) async {
    final n = name.trim();
    if (n.isEmpty || _data.containsKey(n)) return;
    _data[n] = [];
    await _persist();
  }

  Future<void> renameFolder(String oldName, String newName) async {
    if (!_data.containsKey(oldName)) return;
    final n = newName.trim();
    if (n.isEmpty || n == oldName || _data.containsKey(n)) return;
    _data[n] = _data.remove(oldName)!;
    await _persist();
  }

  Future<void> deleteFolder(String name) async {
    if (_data.remove(name) != null) await _persist();
  }

  // Items
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
    final list = _data.putIfAbsent(folder, () => []);
    if (!list.any((e) => e.id == item.id)) {
      list.add(item);
      await _persist();
    }
  }

  Future<void> removeFromFolder(String folder, String id) async {
    final list = _data[folder];
    if (list == null) return;
    list.removeWhere((e) => e.id == id);
    if (list.isEmpty && folder != 'Favourites') _data.remove(folder);
    await _persist();
  }

  Future<bool> toggleInFolder(String folder, FavoriteItem item) async {
    if (contains(folder, item.id)) {
      await removeFromFolder(folder, item.id);
      return false;
    }
    await addToFolder(folder, item);
    return true;
  }

  // Public helpers
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
    bool removed = false;
    _data.forEach((folder, list) {
      final before = list.length;
      list.removeWhere((e) => e.id == id);
      if (list.length < before) removed = true;
    });
    if (removed) await _persist();
  }
}
