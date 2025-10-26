// lib/screens/home_page_screen.dart
import 'dart:async';

// Project imports
import 'package:archivereader/services/favourites_service.dart'; // British spelling in file path
import 'package:archivereader/services/favourites_service_compat.dart';
import 'package:archivereader/services/filters.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_detail_screen.dart';
import 'favourites_screen.dart'; // US spelling in screen name is fine

// ===== Categories (Explore grid) =====
enum Category { classic, books, magazines, comics, video, readingList }

extension CategoryX on Category {
  String get label {
    switch (this) {
      case Category.classic:
        return 'Classic Literature';
      case Category.books:
        return 'Books';
      case Category.magazines:
        return 'Magazines';
      case Category.comics:
        return 'Comics';
      case Category.video:
        return 'Videos';
      case Category.readingList:
        return 'Reading Lists';
    }
  }

  IconData get icon {
    switch (this) {
      case Category.classic:
        return Icons.menu_book_outlined;
      case Category.books:
        return Icons.library_books_outlined;
      case Category.magazines:
        return Icons.article_outlined;
      case Category.comics:
        return Icons.auto_awesome_mosaic_outlined;
      case Category.video:
        return Icons.local_movies_outlined;
      case Category.readingList:
        return Icons.bookmarks_outlined;
    }
  }
}

// ===== Capsule card used for pins & favourites =====
class CollectionCapsuleCard extends StatelessWidget {
  final String identifier;
  final String title;
  final String? thumbnailUrl;
  final int downloads;
  final VoidCallback onTap;
  final bool showPin;
  final VoidCallback? onPinToggle;

  const CollectionCapsuleCard({
    super.key,
    required this.identifier,
    required this.title,
    this.thumbnailUrl,
    required this.downloads,
    required this.onTap,
    this.showPin = false,
    this.onPinToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: const StadiumBorder(),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child:
                      thumbnailUrl != null
                          ? CachedNetworkImage(
                            imageUrl: thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder:
                                (_, __) => const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            errorWidget:
                                (_, __, ___) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.collections,
                                    size: 24,
                                  ),
                                ),
                          )
                          : Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.collections, size: 24),
                          ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.isEmpty ? identifier : title,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$downloads downloads',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (showPin && onPinToggle != null)
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined, size: 20),
                  onPressed: onPinToggle,
                )
              else
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key});

  @override
  State<HomePageScreen> createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> with RouteAware {
  static const _kSfw = 'home_sfw';
  static const _kFav = 'home_fav';
  static const _kDld = 'home_dld';
  static const _pinsKey = 'pinned_collections';

  bool _sfwOnly = false;
  bool _favouritesOnly = false;
  bool _downloadedOnly = false;
  List<String> _pinned = [];

  ArchiveFilters get _filters => ArchiveFilters(
    sfwOnly: _sfwOnly,
    favouritesOnly: _favouritesOnly,
    downloadedOnly: _downloadedOnly,
  );

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadPins();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwOnly = prefs.getBool(_kSfw) ?? false;
      _favouritesOnly = prefs.getBool(_kFav) ?? false;
      _downloadedOnly = prefs.getBool(_kDld) ?? false;
    });
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    setState(() => _pinned = List.of(list));
  }

  Future<void> _addPin(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await prefs.setStringList(_pinsKey, list);
      setState(() => _pinned = List.of(list));
    }
  }

  Future<void> _removePin(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    list.remove(id);
    await prefs.setStringList(_pinsKey, list);
    setState(() => _pinned = List.of(list));
  }

  void _onReorderPins(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final item = _pinned.removeAt(oldIndex);
      _pinned.insert(newIndex, item);
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_pinsKey, _pinned);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0.0,
        titleSpacing: 16.0,
        title: Row(
          children: const <Widget>[
            _BrandMark(),
            SizedBox(width: 8.0),
            _BrandWordmark(),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () {}, child: const Text('ARTBOARD')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
        children: <Widget>[
          const SectionHeader(title: 'Continue watching'),
          const SizedBox(height: 8.0),
          const HList(
            children: <Widget>[
              ResumePlaceholderCard(),
              PosterCard.large(
                title: 'Night of the\nLiving Dead',
                subtitle: 'Play',
              ),
              PosterCard.large(title: 'Nosferatu', subtitle: 'Play'),
              PosterCard.large(
                title: 'CAPTAIN\nAMERICA',
                captionTopRight: '15 mi',
                chip: 'KSV',
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          const SectionHeader(title: 'Continue reading'),
          const SizedBox(height: 8.0),
          const HList(
            children: <Widget>[
              BookCard(
                title: 'LITTLE\nDORRIT',
                author: 'Charles Dick.',
                progressLabel: 'in progress',
              ),
              BookCard(
                title: 'THE COUNT OF\nMONTE CRISTO',
                author: 'Alexandra Dumas',
                progressLabel: 'in progress',
              ),
              BookCard(
                title: "BLACKWOOD'S\nEDINBURGH MAGAZINE",
                author: '',
                progressLabel: 'in progress',
              ),
            ],
          ),
          const SizedBox(height: 16.0),

          // Recommended (Pinned)
          SectionHeader(
            title: 'Recommended collections',
            actionLabel: 'Manage',
            onAction: () => _openManagePins(context),
          ),
          const SizedBox(height: 8.0),
          _CollectionsGrid(
            data: _pinned,
            onTap: (c) => _openCollectionById(context, c.categoryName),
            onReorder: _onReorderPins,
          ),

          const SizedBox(height: 16.0),

          // Explore
          SectionHeader(
            title: 'Explore more',
            actionLabel: 'See all',
            onAction: () => _openExplore(context),
          ),
          const SizedBox(height: 8.0),
          const CategoriesGrid(),

          const SizedBox(height: 16.0),

          // Favourites shelf
          SectionHeader(
            title: 'Favourites',
            actionLabel: 'See all',
            onAction:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                ),
          ),
          const SizedBox(height: 8.0),
          _buildFavouritesShelf(context),

          const SizedBox(height: 16.0),

          // Reading lists
          SectionHeader(
            title: 'Reading lists',
            actionLabel: 'See all',
            onAction:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReadingListScreen()),
                ),
          ),
          const SizedBox(height: 8.0),
          const ReadingListCarousel(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            () => showSearch(
              context: context,
              delegate: _SimpleSearchDelegate(_filters),
            ),
        child: const Icon(Icons.search),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _openCollectionById(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => CollectionDetailScreen(
              categoryName: id,
              customQuery: 'collection:$id',
            ),
      ),
    );
  }

  void _openManagePins(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ManagePinsScreen(
              ids: _pinned,
              onReorder: _onReorderPins,
              onRemove: _removePin,
            ),
      ),
    );
  }

  void _openExplore(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ExploreCollectionsScreen(onPinnedChanged: null),
      ),
    );
  }

  /// Favourites shelf — uses FAVOURITES service (British).
  /// If your service exposes a different getter, change the next line only.
  Widget _buildFavouritesShelf(BuildContext context) {
    final raw = FavoritesService.instance.itemsOrEmpty; // <- adapter
    final favs = raw.map(toFavouriteVm).whereType<FavouriteVm>().toList();

    if (favs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No favorites yet'),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: favs.length,
        itemBuilder: (context, i) {
          final item = favs[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CollectionCapsuleCard(
              identifier: item.identifier,
              title: item.title,
              thumbnailUrl: item.thumbnailUrl,
              downloads: item.downloads,
              onTap: () => _openCollectionById(context, item.identifier),
            ),
          );
        },
      ),
    );
  }
}

// ===== Pinned grid =====
class _CollectionsGrid extends StatelessWidget {
  final List<String> data; // collection identifiers
  final void Function(CollectionMeta) onTap;
  final void Function(int, int) onReorder;

  const _CollectionsGrid({
    required this.data,
    required this.onTap,
    required this.onReorder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No pinned collections'));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: data.length,
      itemBuilder: (context, i) {
        final id = data[i];
        final meta = CollectionMeta(
          categoryName: id,
          title: id
              .split(RegExp(r'[_\-]'))
              .map(
                (s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}',
              )
              .join(' '),
          thumbnailUrl: 'https://archive.org/services/img/$id',
          downloads: 0,
        );
        return CollectionCapsuleCard(
          identifier: meta.categoryName,
          title: meta.title,
          thumbnailUrl: meta.thumbnailUrl,
          downloads: meta.downloads,
          onTap: () => onTap(meta),
          showPin: true,
          onPinToggle: () {}, // no-op in grid; managed in Manage screen
        );
      },
    );
  }
}

// ===== UI helpers / placeholders kept minimal for now =====
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => const Icon(Icons.book, size: 32);
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();
  @override
  Widget build(BuildContext context) => const Text('Archive');
}

class HList extends StatelessWidget {
  final List<Widget> children;
  const HList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

// ===== Placeholders to match layout (keep or swap with real ones) =====
class ResumePlaceholderCard extends StatelessWidget {
  const ResumePlaceholderCard({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class PosterCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? captionTopRight;
  final String? chip;
  const PosterCard.large({
    super.key,
    required this.title,
    this.subtitle,
    this.captionTopRight,
    this.chip,
  });
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class BookCard extends StatelessWidget {
  final String title;
  final String author;
  final String progressLabel;
  const BookCard({
    super.key,
    required this.title,
    required this.author,
    required this.progressLabel,
  });
  @override
  Widget build(BuildContext context) => const SizedBox();
}

// ===== Explore grid =====
class CategoriesGrid extends StatelessWidget {
  const CategoriesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.2,
      children:
          Category.values.map((c) {
            return Card(
              child: InkWell(
                onTap: () {
                  final id = switch (c) {
                    Category.classic => 'gutenberg',
                    Category.books => 'books',
                    Category.magazines => 'magazines',
                    Category.comics => 'comic_books',
                    Category.video => 'movies',
                    Category.readingList => 'readinglists',
                  };
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => CollectionDetailScreen(
                            categoryName: id,
                            customQuery: 'collection:$id',
                          ),
                    ),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(c.icon, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      c.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }
}

// ===== Reading lists placeholder =====
class ReadingListCarousel extends StatelessWidget {
  const ReadingListCarousel({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class ExploreCollectionsScreen extends StatelessWidget {
  final void Function(String)? onPinnedChanged;
  const ExploreCollectionsScreen({super.key, this.onPinnedChanged});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Explore Collections')),
    body: const Center(child: Text('Coming soon')),
  );
}

class ManagePinsScreen extends StatelessWidget {
  final List<String> ids;
  final void Function(int, int) onReorder;
  final ValueChanged<String> onRemove;
  const ManagePinsScreen({
    super.key,
    required this.ids,
    required this.onReorder,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage Pinned')),
    body: const Center(child: Text('Coming soon')),
  );
}

class MagazinesHubScreen extends StatelessWidget {
  final ArchiveFilters filters;
  const MagazinesHubScreen({super.key, required this.filters});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Magazines')),
    body: const Center(child: Text('Coming soon')),
  );
}

class ReadingListScreen extends StatelessWidget {
  const ReadingListScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reading Lists')),
    body: const Center(child: Text('Coming soon')),
  );
}

// ===== Local meta model for grid =====
class CollectionMeta {
  final String categoryName;
  final String title;
  final String? thumbnailUrl;
  final int downloads;
  CollectionMeta({
    required this.categoryName,
    required this.title,
    this.thumbnailUrl,
    required this.downloads,
  });
}

// ===== Search Delegate (unchanged) =====
class _SimpleSearchDelegate extends SearchDelegate<void> {
  _SimpleSearchDelegate(this.filters);
  final ArchiveFilters filters;

  @override
  String? get searchFieldLabel => 'Search Archive (title/subject/creator)…';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      onPressed: query.isEmpty ? null : () => query = '',
      icon: const Icon(Icons.clear),
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    final advQuery =
        '(title:"$q" OR subject:"$q" OR description:"$q" OR creator:"$q")';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: 'Search',
                customQuery: advQuery,
                filters: filters,
              ),
        ),
      );
      close(context, null);
    });
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();
}
