// lib/screens/home_page_screen.dart
import 'dart:async';

// Project imports
import 'package:archivereader/services/favourites_service.dart'; // British spelling in file path
import 'package:archivereader/services/favourites_service_compat.dart';
import 'package:archivereader/services/filters.dart';
import 'package:archivereader/services/recent_progress_service.dart';
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
  final int? downloads;
  final VoidCallback? onTap;

  const CollectionCapsuleCard({
    super.key,
    required this.identifier,
    required this.title,
    this.thumbnailUrl,
    this.downloads,
    this.onTap,
  });

  String _thumbForId(String id) => 'https://archive.org/services/img/$id';

  @override
  Widget build(BuildContext context) {
    final imgUrl = thumbnailUrl ?? _thumbForId(identifier); // ← fallback
    return Card(
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: CachedNetworkImage(
                  imageUrl: imgUrl, // ← always non-null now
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget:
                      (_, __, ___) => const Icon(Icons.image_not_supported),
                ),
              ),
              const SizedBox(width: 10),
              Text(title, overflow: TextOverflow.ellipsis),
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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
        children: <Widget>[
          const SectionHeader(title: 'Continue reading'),
          const SizedBox(height: 8.0),
          _BuildContinueReading(),

          const SectionHeader(title: 'Continue watching'),
          const SizedBox(height: 8.0),
          _BuildContinueWatching(),

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
    final List<FavoriteItem> raw =
        FavoritesService.instance.itemsOrEmpty.cast<FavoriteItem>();

    final List<FavouriteVm> favs =
        raw.map<FavouriteVm?>(toFavouriteVm).whereType<FavouriteVm>().toList();

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
  Widget build(BuildContext context) =>
      const Icon(Icons.home_outlined, size: 32);
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();
  @override
  Widget build(BuildContext context) => const Text('Home');
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
                    Category.comics => 'comics_inbox',
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

class _BuildContinueReading extends StatelessWidget {
  const _BuildContinueReading();

  // --------------------------------------------------------------
  // Helper: turn a raw id (file-path or identifier) into the
  //         Archive.org *item identifier* that we can use for
  //         __ia_thumb.jpg
  // --------------------------------------------------------------
  String _itemId(String rawId) {
    // 1. Split on '/'  →  "item123/Invincible 09.pdf"  →  ["item123","Invincible 09.pdf"]
    // 2. Take the part *before* the last slash (the item identifier)
    // 3. Remove any file extension just in case
    final parts = rawId.split('/');
    final fileName = parts.last;
    return fileName.split('.').first; // removes .pdf, .cbz, .epub, …
  }

  String _thumbUrl(String rawId) =>
      'https://archive.org/download/${_itemId(rawId)}/__ia_thumb.jpg';

  @override
  Widget build(BuildContext context) {
    // Newest first, keep only pdf/epub/cbz/cbr/zip/rar
    final recent =
        RecentProgressService.instance.recent(limit: 30).where((e) {
          final k = (e['kind'] as String?)?.toLowerCase();
          return k == 'pdf' ||
              k == 'epub' ||
              k == 'cbz' ||
              k == 'cbr' ||
              k == 'zip' ||
              k == 'rar';
        }).toList();

    if (recent.isEmpty) {
      return const SizedBox(
        height: 48,
        child: Center(child: Text('No recent reading')),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final e = recent[i];
          final String rawId = e['id'] as String; // <-- may be "item/file.pdf"
          final String itemId = _itemId(rawId); // <-- clean identifier
          final title = (e['title'] as String?) ?? itemId;

          // Prefer a thumb that the service already saved, otherwise use __ia_thumb.jpg
          final thumb = (e['thumb'] as String?) ?? _thumbUrl(rawId);

          // ---------- progress ----------
          double? progress;
          String? progressLabel;

          final p = e['progress'];
          if (p is num) progress = p.toDouble().clamp(0.0, 1.0);

          final cur = e['currentPage'];
          final tot = e['totalPages'];
          if (cur is num && tot is num && tot > 0) {
            progress = (cur / tot).clamp(0.0, 1.0);
            progressLabel = 'Page ${cur.toInt()} of ${tot.toInt()}';
          }

          // ---------- card ----------
          return _ResumeBookCard(
            id: itemId, // <-- clean identifier for the query
            title: title,
            thumb: thumb,
            progress: progress,
            progressLabel: progressLabel,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => CollectionDetailScreen(
                        categoryName: title,
                        customQuery:
                            'identifier:$itemId', // <-- uses the clean id
                      ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ResumeBookCard extends StatelessWidget {
  final String id;
  final String title;
  final String thumb;
  final double? progress; // 0..1
  final String? progressLabel; // optional “Page X of Y”
  final VoidCallback onTap;

  const _ResumeBookCard({
    required this.id,
    required this.title,
    required this.thumb,
    required this.onTap,
    this.progress,
    this.progressLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  errorWidget:
                      (_, __, ___) => Image.network(
                        'https://archive.org/download/$id/$id.jpg',
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                ),
              ),
              if (progress != null) ...[
                LinearProgressIndicator(value: progress),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    progressLabel ??
                        '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildContinueWatching extends StatelessWidget {
  const _BuildContinueWatching();

  @override
  Widget build(BuildContext context) {
    // Pull recent, keep only videos, newest first
    final recent =
        RecentProgressService.instance
            .recent(limit: 20)
            .where((e) => (e['kind'] as String?) == 'video')
            .toList();

    if (recent.isEmpty) {
      return const SizedBox(
        height: 48,
        child: Center(child: Text('No recent videos')),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final e = recent[i];
          final id = e['id'] as String;
          final title = (e['title'] as String?) ?? id;
          final thumb =
              (e['thumb'] as String?) ?? 'https://archive.org/services/img/$id';

          return _ResumeVideoCard(
            id: id,
            title: title,
            thumb: thumb,
            onTap: () {
              // Jump to a screen that lists just this item, then the user picks a file;
              // your CollectionDetailScreen will open the chooser from there.
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => CollectionDetailScreen(
                        categoryName: title,
                        customQuery: 'identifier:$id', // shows only this item
                      ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ResumeVideoCard extends StatelessWidget {
  final String id;
  final String title;
  final String thumb;
  final VoidCallback onTap;

  const _ResumeVideoCard({
    required this.id,
    required this.title,
    required this.thumb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  errorWidget:
                      (_, __, ___) => Image.network(
                        'https://archive.org/download/$id/$id.jpg',
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
