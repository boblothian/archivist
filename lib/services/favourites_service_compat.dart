// lib/services/favourites_service_compat.dart
// Compatibility layer – works even if other parts of the app use a different
// FavoritesService shape (old versions, tests, etc.).

import 'package:archivereader/services/favourites_service.dart';

import '../utils/archive_helpers.dart';

/// A tiny view-model used by UI that only needs identifier / title / thumb.
class FavouriteVm {
  final String identifier;
  final String title;
  final String? thumbnailUrl;
  final int? downloads;

  const FavouriteVm({
    required this.identifier,
    required this.title,
    this.thumbnailUrl,
    this.downloads,
  });
}

/// Convert a **new** `FavoriteItem` (with `files`) into the old VM.
FavouriteVm? toFavouriteVm(FavoriteItem it) {
  final thumb = it.thumb ?? it.url ?? archiveThumbUrl(it.id);
  return FavouriteVm(
    identifier: it.id,
    title: it.title,
    thumbnailUrl: thumb,
    downloads: null,
  );
}

/// ---------------------------------------------------------------------
/// Extension – safe access to the favourites list no matter what the
/// service exposes (`favourites`, `favorites`, `items`, `allItems`, …)
/// ---------------------------------------------------------------------
extension FavoritesServiceCompat on FavoritesService {
  /// Returns any list that looks like favourites, otherwise `[]`.
  List<dynamic> get itemsOrEmpty {
    final self = this as dynamic;

    // 1. Try public getters that exist in the current service
    try {
      final v = self.allItems;
      if (v is List) return v;
    } catch (_) {}

    try {
      final v = self.favourites;
      if (v is List) return v;
    } catch (_) {}

    try {
      final v = self.favorites;
      if (v is List) return v;
    } catch (_) {}

    try {
      final v = self.items;
      if (v is List) return v;
    } catch (_) {}

    // 2. Fallback – read private `_data` map (used by the current impl)
    try {
      final Map data = self._data;
      final List<dynamic> all = [];
      for (var list in data.values) {
        if (list is List) all.addAll(list);
      }
      return all;
    } catch (_) {}

    return const <dynamic>[];
  }
}

/// ---------------------------------------------------------------------
/// Best-effort field extractors – work with **any** favourite object
/// (old VM, new FavoriteItem, or even raw JSON maps).
/// ---------------------------------------------------------------------
String favId(dynamic o) {
  try {
    final v = (o as dynamic).identifier;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  try {
    final v = (o as dynamic).id;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  return '';
}

String favTitle(dynamic o) {
  try {
    final v = (o as dynamic).title;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  try {
    final v = (o as dynamic).name;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  return '';
}

String? favThumb(dynamic o) {
  try {
    final v = (o as dynamic).thumbnailUrl;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  try {
    final v = (o as dynamic).thumbnail;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  try {
    final v = (o as dynamic).thumb;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  try {
    final v = (o as dynamic).image;
    if (v is String && v.isNotEmpty) return v;
  } catch (_) {}
  return null;
}

int favDownloads(dynamic o) {
  try {
    final v = (o as dynamic).downloads;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
  } catch (_) {}
  return 0;
}
