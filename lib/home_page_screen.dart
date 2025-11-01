// lib/screens/home_page_screen.dart
import 'dart:async';
import 'dart:io';

// Project imports
import 'package:archivereader/pdf_viewer_screen.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/favourites_service_compat.dart';
import 'package:archivereader/services/filters.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/text_viewer_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cbz_viewer_screen.dart';
import 'collection_detail_screen.dart';
import 'utils/archive_helpers.dart';
import 'utils/external_launch.dart';

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

  @override
  Widget build(BuildContext context) {
    final imgUrl = thumbnailUrl ?? archiveThumbUrl(identifier);
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
                  imageUrl: imgUrl,
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
          children: const <Widget>[SizedBox(width: 8.0), _BrandWordmark()],
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

// ===== UNIFIED CARD (PDF + VIDEO) =====
class _ResumeMediaCard extends StatelessWidget {
  final String id;
  final String title;
  final String thumb;
  final double progress;
  final String? progressLabel;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _ResumeMediaCard({
    required this.id,
    required this.title,
    required this.thumb,
    required this.progress,
    this.progressLabel,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 220,
      child: Card(
        shape: const RoundedRectangleBorder(),
        elevation: 0,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[300]),
                  errorWidget:
                      (_, __, ___) =>
                          const Icon(Icons.play_circle_outline, size: 40),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (progressLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        progressLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== CONTINUE READING (PDF/EPUB/CBZ/CBR/TXT) =====
class _BuildContinueReading extends StatelessWidget {
  const _BuildContinueReading();

  // Prettify the file name the same way ArchiveItemScreen does
  String _prettify(String name) {
    name = name.replaceAll('.pdf', '');
    final match = RegExp(r'^(\d+)[_\s-]+(.*)').firstMatch(name);
    String number = '';
    String title = name;

    if (match != null) {
      number = match.group(1)!;
      title = match.group(2)!;
    }

    title = title.replaceAll(RegExp(r'[_-]+'), ' ');
    title = title
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return number.isNotEmpty ? '$number. $title' : title;
  }

  // Open the exact viewer with the cached file
  Future<void> _openResumeFile({
    required BuildContext context,
    required String id,
    required String title,
    required String fileUrl,
    required String fileName,
    required String kind,
  }) async {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.cbz') || lower.endsWith('.cbr')) {
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CbzViewerScreen(
                url: fileUrl,
                filenameHint: fileName,
                title: title,
                identifier: id,
              ),
        ),
      );
    } else if (lower.endsWith('.txt')) {
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => TextViewerScreen(
                url: fileUrl,
                filenameHint: fileName,
                identifier: id,
                title: title,
              ),
        ),
      );
    } else {
      // PDF (or unknown) – use the cached file if it exists
      final tempDir = await getTemporaryDirectory();
      final localFile = File('${tempDir.path}/$fileName');
      final exists = await localFile.exists();

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => PdfViewerScreen(
                file: exists ? localFile : null,
                url: exists ? null : fileUrl,
                filenameHint: fileName,
                identifier: id,
                title: title,
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RecentProgressService.instance.version,
      builder: (context, _, __) {
        final recent =
            RecentProgressService.instance
                .recent(limit: 30)
                .where(
                  (e) =>
                      [
                        'pdf',
                        'epub',
                        'cbz',
                        'cbr',
                        'txt',
                      ].contains(e['kind']) ||
                      (e['fileName'] as String?)?.toLowerCase().endsWith(
                            '.txt',
                          ) ==
                          true,
                )
                .toList();

        if (recent.isEmpty) {
          return const SizedBox(
            height: 48,
            child: Center(
              child: Text(
                'No recent reading',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8)),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, i) {
                  final e = recent[i];
                  final id = e['id'] as String;
                  final rawTitle = (e['title'] as String?) ?? id;
                  final fileName = e['fileName'] as String?;
                  final fileUrl = e['fileUrl'] as String?;
                  final kind = (e['kind'] as String?) ?? 'pdf';

                  // ---- THUMBNAIL ----
                  // Prefer the thumbnail saved with the file entry (most accurate)
                  final thumb =
                      (e['thumb'] as String?) ??
                      'https://archive.org/services/img/$id';

                  // ---- TITLE ----
                  // Show the prettified file name, fall back to collection title
                  final displayTitle =
                      fileName != null ? _prettify(fileName) : rawTitle;

                  // ---- PROGRESS ----
                  double progress = 0.0;
                  String? progressLabel;

                  if (kind == 'pdf') {
                    final page = e['page'] as int?;
                    final total = e['total'] as int?;
                    if (page != null && total != null && total > 0) {
                      progress = page / total;
                      progressLabel = 'Page $page of $total';
                    }
                  } else if (kind == 'epub') {
                    final percent = (e['percent'] as double?) ?? 0.0;
                    progress = percent;
                    progressLabel =
                        percent > 0
                            ? '${(percent * 100).toStringAsFixed(0)}%'
                            : null;
                  }

                  return _ResumeMediaCard(
                    id: id,
                    title: displayTitle,
                    thumb: thumb,
                    progress: progress,
                    progressLabel: progressLabel,
                    onTap: () async {
                      if (fileUrl == null || fileName == null) {
                        debugPrint(
                          'ERROR: Missing fileUrl/fileName for recent entry $id',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cannot resume: missing file info'),
                          ),
                        );
                        return;
                      }

                      await _openResumeFile(
                        context: context,
                        id: id,
                        title: displayTitle,
                        fileUrl: fileUrl,
                        fileName: fileName,
                        kind: kind,
                      );
                    },
                    onDelete: () => RecentProgressService.instance.remove(id),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===== CONTINUE WATCHING (VIDEO) — OPENS IN VLC/MX PLAYER =====
class _BuildContinueWatching extends StatelessWidget {
  const _BuildContinueWatching();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RecentProgressService.instance.version,
      builder: (context, _, __) {
        final recent =
            RecentProgressService.instance
                .recent(limit: 30)
                .where((e) => e['kind'] == 'video')
                .toList();

        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Continue watching',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, i) {
                  final e = recent[i];
                  final id = e['id'] as String;
                  final title = (e['title'] as String?) ?? id;
                  final thumb =
                      (e['thumb'] as String?) ??
                      'https://archive.org/services/img/$id';
                  final fileUrl = e['fileUrl'] as String?;
                  final fileName = e['fileName'] as String?;
                  final percent = (e['percent'] as double?) ?? 0.0;

                  return _ResumeMediaCard(
                    id: id,
                    title: title,
                    thumb: thumb,
                    progress: percent,
                    progressLabel:
                        percent > 0
                            ? '${(percent * 100).toStringAsFixed(0)}% watched'
                            : 'Tap to open',
                    onTap: () async {
                      if (fileUrl == null || fileName == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No video file recorded.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Opening: $fileName',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: Colors.black87,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );

                      String mime = 'video/*';
                      final ext = fileName.toLowerCase();
                      if (ext.endsWith('.mp4') || ext.endsWith('.m4v')) {
                        mime = 'video/mp4';
                      } else if (ext.endsWith('.webm')) {
                        mime = 'video/webm';
                      } else if (ext.endsWith('.mkv')) {
                        mime = 'video/x-matroska';
                      } else if (ext.endsWith('.m3u8')) {
                        mime = 'application/vnd.apple.mpegurl';
                      }

                      try {
                        await openExternallyWithChooser(
                          url: fileUrl,
                          mimeType: mime,
                          chooserTitle: 'Open with',
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to open: $e')),
                          );
                        }
                      }
                    },
                    onDelete: () => RecentProgressService.instance.remove(id),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===== REST OF FILE (UNCHANGED) =====
class _CollectionsGrid extends StatelessWidget {
  final List<String> data;
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

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();
  @override
  Widget build(BuildContext context) => const Text('Home');
}

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
