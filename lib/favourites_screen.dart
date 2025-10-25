// lib/screens/favourites_screen.dart
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/filters.dart';
import 'package:flutter/material.dart';

import 'collection_detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  final String? initialFolder;

  const FavoritesScreen({super.key, this.initialFolder});

  static const int _maxIdsPerQuery = 80; // keep URLs safe

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesService.instance;
    final folderName = initialFolder ?? 'All';

    final items =
        initialFolder != null ? svc.itemsIn(initialFolder!) : svc.allItems;

    final ids = items
        .map((e) => e.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (ids.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Favorites: $folderName')),
        body: const Center(child: Text('No favourites yet.')),
      );
    }

    String _buildQuery(List<String> chunk) =>
        'identifier:(${chunk.map((id) => '"$id"').join(' OR ')})';

    if (ids.length <= _maxIdsPerQuery) {
      return Scaffold(
        appBar: AppBar(title: Text('Favorites: $folderName')),
        body: CollectionDetailScreen(
          categoryName: 'Favourites',
          customQuery: _buildQuery(ids),
          // We already filter by identifiers; no need to toggle favouritesOnly/downloadedOnly.
          filters: const ArchiveFilters(
            sfwOnly: false,
            favouritesOnly: false,
            downloadedOnly: false,
          ),
        ),
      );
    }

    // Many favourites — split across tabs, each tab renders a standard CollectionDetailScreen
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += _maxIdsPerQuery) {
      chunks.add(
        ids.sublist(
          i,
          i + _maxIdsPerQuery > ids.length ? ids.length : i + _maxIdsPerQuery,
        ),
      );
    }

    return DefaultTabController(
      length: chunks.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Favorites: $folderName'),
          bottom: TabBar(
            isScrollable: true,
            tabs: List.generate(
              chunks.length,
              (i) => Tab(text: 'Set ${i + 1}'),
            ),
          ),
        ),
        body: TabBarView(
          children:
              chunks.map((chunk) {
                return CollectionDetailScreen(
                  categoryName: 'Favourites',
                  customQuery: _buildQuery(chunk),
                  filters: const ArchiveFilters(
                    sfwOnly: false,
                    favouritesOnly: false,
                    downloadedOnly: false,
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }
}
