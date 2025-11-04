// lib/collection_store.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// -----------------------------------------------------------------
/// Local file model
/// -----------------------------------------------------------------
class LocalCollection {
  final String id, title, path, extension;
  LocalCollection({
    required this.id,
    required this.title,
    required this.path,
    required this.extension,
  });

  factory LocalCollection.fromFile(File file) {
    final ext = p.extension(file.path).toLowerCase();
    final name = p.basenameWithoutExtension(file.path);
    return LocalCollection(
      id: file.path,
      title: name,
      path: file.path,
      extension: ext,
    );
  }

  @override
  bool operator ==(Object o) => o is LocalCollection && id == o.id;
  @override
  int get hashCode => id.hashCode;
}

/// -----------------------------------------------------------------
/// Isolate scanner (top-level)
/// -----------------------------------------------------------------
Future<List<LocalCollection>> _scanLocalCollectionsIsolated(
  String rootPath,
) async {
  final dir = Directory(rootPath);
  final result = <LocalCollection>[];
  if (!await dir.exists()) return result;

  final supported = {'.cbz', '.cbr', '.pdf', '.epub'};
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File &&
        supported.contains(p.extension(entity.path).toLowerCase())) {
      result.add(LocalCollection.fromFile(entity));
    }
  }
  debugPrint('Found ${result.length} local collections');
  return result;
}

/// -----------------------------------------------------------------
/// Pinned IDs helpers
/// -----------------------------------------------------------------
Future<List<String>> _loadPinnedIdsMain() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('pinned_collections') ?? const [];
}

Future<void> _savePinnedIdsMain(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('pinned_collections', ids);
}

/// -----------------------------------------------------------------
/// SINGLETON STORE – NO of(), NO InheritedWidget
/// -----------------------------------------------------------------
class CollectionStore extends ChangeNotifier {
  // Singleton instance
  static final CollectionStore _instance = CollectionStore._internal();
  factory CollectionStore() => _instance;
  CollectionStore._internal();

  // Global key to rebuild UI when needed
  static final GlobalKey _rebuildKey = GlobalKey();

  // Data
  List<String> _pinnedIds = const [];
  List<LocalCollection> _localCollections = [];
  bool _pinnedLoading = false, _localLoading = false;

  // Getters
  List<String> get pinnedIds => _pinnedIds;
  List<LocalCollection> get localCollections => _localCollections;
  bool get isPinnedLoading => _pinnedLoading;
  bool get isLocalLoading => _localLoading;

  // -----------------------------------------------------------------
  // Pinned
  // -----------------------------------------------------------------
  Future<void> loadPinned() async {
    if (_pinnedLoading) return;
    _pinnedLoading = true;
    notifyListeners();
    try {
      _pinnedIds = await _loadPinnedIdsMain();
    } finally {
      _pinnedLoading = false;
      notifyListeners();
    }
  }

  Future<void> pin(String id) async {
    final t = id.trim();
    if (t.isEmpty || _pinnedIds.contains(t)) return;
    _pinnedIds = [..._pinnedIds, t];
    await _savePinnedIdsMain(_pinnedIds);
    notifyListeners();
  }

  Future<void> unpin(String id) async {
    final t = id.trim();
    if (!_pinnedIds.contains(t)) return;
    _pinnedIds = _pinnedIds.where((e) => e != t).toList();
    await _savePinnedIdsMain(_pinnedIds);
    notifyListeners();
  }

  // -----------------------------------------------------------------
  // Local collections
  // -----------------------------------------------------------------
  Future<void> loadLocal(String path) async {
    if (_localLoading) return;
    _localLoading = true;
    notifyListeners();
    try {
      _localCollections = await compute(_scanLocalCollectionsIsolated, path);
    } finally {
      _localLoading = false;
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------
  // Rebuild any widget that uses the key
  // -----------------------------------------------------------------
  static void rebuild() {
    _rebuildKey.currentState?.setState(() {});
  }
}
