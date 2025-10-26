// lib/services/favourites_service_compat.dart
// Adapter so code works no matter what your FavoritesService exposes.

import 'package:archivereader/services/favourites_service.dart';

/// Minimal view model used by the shelf.
class FavouriteVm {
  final String identifier;
  final String title;
  final String? thumbnailUrl;
  final int downloads;

  const FavouriteVm({
    required this.identifier,
    required this.title,
    required this.thumbnailUrl,
    required this.downloads,
  });
}

extension FavoritesServiceCompat on FavoritesService {
  /// Returns the favourites list regardless of whether your service
  /// exposes it as `favourites`, `favorites`, or `items`.
  List<dynamic> get itemsOrEmpty {
    // Access through `dynamic` and swallow missing getters.
    final self = this as dynamic;
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
    return const <dynamic>[];
  }
}

/// Best-effort field extractors from unknown favourite item types.
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

/// Map any service item to the shelf view model; empty id = skip.
FavouriteVm? toFavouriteVm(dynamic raw) {
  final id = favId(raw);
  if (id.isEmpty) return null;
  return FavouriteVm(
    identifier: id,
    title: favTitle(raw).isNotEmpty ? favTitle(raw) : id,
    thumbnailUrl: favThumb(raw),
    downloads: favDownloads(raw),
  );
}
