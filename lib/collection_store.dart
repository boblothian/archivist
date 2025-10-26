// lib/collection_store.dart
import 'package:flutter/cupertino.dart';

/// In-memory store for Home "Recommended collections".
/// Uses **real Internet Archive slugs** so taps hit the live API.
class CollectionsHomeState extends ChangeNotifier {
  final List<CollectionMeta> _pinned = <CollectionMeta>[];

  // If the user hasn’t pinned anything yet, show these valid defaults.
  List<CollectionMeta> get pinned =>
      _pinned.isEmpty ? _seed.take(3).toList() : List.unmodifiable(_pinned);

  bool isPinned(String categoryName) =>
      _pinned.any((c) => c.categoryName == categoryName);

  void pin(CollectionMeta c) {
    if (isPinned(c.categoryName)) return;
    _pinned.add(c);
    notifyListeners();
  }

  void unpin(String categoryName) {
    _pinned.removeWhere((c) => c.categoryName == categoryName);
    notifyListeners();
  }

  List<CollectionMeta> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _seed;
    return _seed
        .where(
          (c) =>
              c.title.toLowerCase().contains(q) ||
              c.categoryName.toLowerCase().contains(q) ||
              c.tags.any((t) => t.toLowerCase().contains(q)),
        )
        .toList();
  }
}

class CollectionsHomeScope extends InheritedNotifier<CollectionsHomeState> {
  CollectionsHomeScope({required Widget child, Key? key})
    : super(notifier: CollectionsHomeState(), child: child, key: key);

  static CollectionsHomeState of(context) =>
      context
          .dependOnInheritedWidgetOfExactType<CollectionsHomeScope>()!
          .notifier!;
}

class CollectionMeta {
  final String categoryName; // slug expected by your CollectionDetailScreen
  final String title; // display title
  final List<String> tags;
  const CollectionMeta({
    required this.categoryName,
    required this.title,
    required this.tags,
  });
}

/// Real Internet Archive collection slugs (expand as needed).
const List<CollectionMeta> _seed = <CollectionMeta>[
  CollectionMeta(
    categoryName: 'classic_tv',
    title: 'Classic TV',
    tags: ['television', 'video', 'retro'],
  ),
  CollectionMeta(
    categoryName: 'prelinger',
    title: 'Prelinger Archives',
    tags: ['ephemera', 'industrial', 'video', 'history'],
  ),
  CollectionMeta(
    categoryName: 'animationandcartoons',
    title: 'Animation & Cartoons',
    tags: ['video', 'cartoons', 'animation'],
  ),
  CollectionMeta(
    categoryName: 'etree',
    title: 'Live Music Archive',
    tags: ['music', 'lossless', 'audio'],
  ),
  CollectionMeta(
    categoryName: 'opensource',
    title: 'Open Source Software',
    tags: ['software', 'isos', 'linux', 'bsd'],
  ),
  CollectionMeta(
    categoryName: 'americana', // American Libraries
    title: 'American Libraries',
    tags: ['books', 'library', 'texts', 'us'],
  ),
];
