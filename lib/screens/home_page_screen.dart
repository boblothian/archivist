// lib/screens/home_page_screen.dart
import 'dart:async';
import 'dart:io';

// Project imports
import 'package:archivereader/screens/pdf_viewer_screen.dart';
import 'package:archivereader/screens/text_viewer_screen.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/favourites_service_compat.dart';
import 'package:archivereader/services/filters.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/services/thumb_override_service.dart';
import 'package:archivereader/ui/shell/root_shell.dart'; // <-- Added for app bar control
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../media/media_player_ops.dart';
import '../utils/archive_helpers.dart';
import '../widgets/big_section_header.dart';
import 'archive_item_screen.dart';
import 'cbz_viewer_screen.dart';
import 'collection_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level helper: resolve best poster using ThumbOverrideService
// ─────────────────────────────────────────────────────────────────────────────
Future<String> _resolveThumb(String id, String currentThumb) async {
  final m = <String, String>{'identifier': id, 'thumb': currentThumb};
  await ThumbOverrideService.instance.applyToItemMaps([m]);
  return (m['thumb']?.trim().isNotEmpty == true) ? m['thumb']! : currentThumb;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer to update title when this screen is visible
    final modalRoute = ModalRoute.of(context);
    if (modalRoute is PageRoute) {
      final observer =
          Navigator.of(
            context,
          ).widget.observers.whereType<RouteObserver>().firstOrNull;
      observer?.subscribe(this, modalRoute);
    }
  }

  @override
  void dispose() {
    final observer =
        Navigator.of(
          context,
        ).widget.observers.whereType<RouteObserver>().firstOrNull;
    observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    RootShell.appBarKey.currentState?.setPageDesc('Home');
  }

  @override
  void didPopNext() {
    RootShell.appBarKey.currentState?.setPageDesc('Home');
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
      children: const <Widget>[
        BigSectionHeader('Continue reading'),
        SizedBox(height: 8.0),
        _BuildContinueReading(),

        SizedBox(height: 24.0),
        BigSectionHeader('Recently watched'),
        SizedBox(height: 8.0),
        _BuildContinueWatching(),

        // NEW: Recently listened shelf
        SizedBox(height: 24.0),
        BigSectionHeader('Recently listened'),
        SizedBox(height: 8.0),
        _BuildContinueListening(),

        SizedBox(height: 24.0),
        FeaturedCollectionsCarousel(),

        SizedBox(height: 24.0),
        ExploreByCategory(),
      ],
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

// ===== UNIFIED CARD (PDF + VIDEO + AUDIO) =====
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
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 140,
      height: 220,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
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
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white,
                          ),
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
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== CONTINUE READING (PDF/EPUB/CBZ/CBR/TXT) =====
class _BuildContinueReading extends StatelessWidget {
  const _BuildContinueReading();

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
          return const Padding(
            padding: EdgeInsets.only(top: 8.0),
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

                  final fallback = 'https://archive.org/services/img/$id';
                  final initialThumb = (e['thumb'] as String?) ?? fallback;

                  final displayTitle =
                      fileName != null ? _prettify(fileName) : rawTitle;

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

                  return FutureBuilder<String>(
                    future: _resolveThumb(id, initialThumb),
                    initialData: initialThumb,
                    builder: (context, snap) {
                      final thumbToUse = snap.data ?? initialThumb;
                      return _ResumeMediaCard(
                        id: id,
                        title: displayTitle,
                        thumb: thumbToUse,
                        progress: progress,
                        progressLabel: progressLabel,
                        onTap: () async {
                          if (fileUrl == null || fileName == null) {
                            debugPrint(
                              'ERROR: Missing fileUrl/fileName for recent entry $id',
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cannot resume: missing file info',
                                ),
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
                        onDelete:
                            () => RecentProgressService.instance.remove(id),
                      );
                    },
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

// ===== CONTINUE WATCHING (VIDEO) — Resumes using positionMs if available =====
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

        if (recent.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Center(
              child: Text(
                'No recent watching',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  final fileUrl = e['fileUrl'] as String?;
                  final fileName = e['fileName'] as String?;

                  // New: prefer positionMs/durationMs when present
                  final positionMs = (e['positionMs'] as int?) ?? 0;
                  final durationMs = (e['durationMs'] as int?) ?? 0;
                  double percent;
                  if (durationMs > 0 && positionMs >= 0) {
                    percent = positionMs / durationMs;
                  } else {
                    percent = (e['percent'] as double?) ?? 0.0;
                  }

                  final fallback = 'https://archive.org/services/img/$id';
                  final initialThumb = (e['thumb'] as String?) ?? fallback;

                  return FutureBuilder<String>(
                    future: _resolveThumb(id, initialThumb),
                    initialData: initialThumb,
                    builder: (context, snap) {
                      final thumbToUse = snap.data ?? initialThumb;

                      return _ResumeMediaCard(
                        id: id,
                        title: title,
                        thumb: thumbToUse,
                        progress: percent.clamp(0.0, 1.0),
                        progressLabel:
                            (percent > 0)
                                ? '${(percent * 100).toStringAsFixed(0)}% watched'
                                : 'Tap to open',
                        onTap: () async {
                          if (fileUrl == null || fileName == null) {
                            // Fallback: open the full item page if we can’t resume a specific file
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No video file recorded; opening item…',
                                ),
                              ),
                            );
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => ArchiveItemScreen(
                                      title: title,
                                      identifier: id,
                                      files:
                                          const <
                                            Map<String, String>
                                          >[], // unknown here
                                      parentThumbUrl: thumbToUse,
                                    ),
                              ),
                            );
                            return;
                          }

                          // Use the centralized in-app player with resume time
                          try {
                            await MediaPlayerOps.playVideo(
                              context,
                              url: fileUrl,
                              identifier: id,
                              title: title,
                              startPositionMs: positionMs, // <-- resume time
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to play: $e')),
                            );
                          }
                        },
                        onDelete:
                            () => RecentProgressService.instance.remove(id),
                      );
                    },
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

// ===== CONTINUE LISTENING (AUDIO) — Resumes using positionMs if available =====
class _BuildContinueListening extends StatelessWidget {
  const _BuildContinueListening();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RecentProgressService.instance.version,
      builder: (context, _, __) {
        final recent =
            RecentProgressService.instance
                .recent(limit: 30)
                .where((e) => (e['kind'] as String?) == 'audio')
                .toList();

        if (recent.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Center(
              child: Text(
                'No recent listening',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return SizedBox(
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
              final fileUrl = e['fileUrl'] as String?;
              final fileName = e['fileName'] as String?;

              final positionMs = (e['positionMs'] as int?) ?? 0;
              final durationMs = (e['durationMs'] as int?) ?? 0;
              final percent =
                  (durationMs > 0 && positionMs >= 0)
                      ? (positionMs / durationMs)
                      : ((e['percent'] as double?) ?? 0.0);

              final fallback = 'https://archive.org/services/img/$id';
              final initialThumb = (e['thumb'] as String?) ?? fallback;

              return FutureBuilder<String>(
                future: _resolveThumb(id, initialThumb),
                initialData: initialThumb,
                builder: (context, snap) {
                  final thumbToUse = snap.data ?? initialThumb;
                  return _ResumeMediaCard(
                    id: id,
                    title: title,
                    thumb: thumbToUse,
                    progress: percent.clamp(0.0, 1.0),
                    progressLabel:
                        percent > 0
                            ? '${(percent * 100).toStringAsFixed(0)}% listened'
                            : 'Tap to play',
                    onTap: () async {
                      if (fileUrl == null || fileName == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No audio file recorded; opening item…',
                            ),
                          ),
                        );
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => ArchiveItemScreen(
                                  title: title,
                                  identifier: id,
                                  files: const <Map<String, String>>[],
                                  parentThumbUrl: thumbToUse,
                                ),
                          ),
                        );
                        return;
                      }

                      try {
                        await MediaPlayerOps.playAudio(
                          context,
                          url: fileUrl,
                          identifier: id,
                          title: title,
                          startPositionMs: positionMs, // <-- resume audio
                        );
                      } catch (err) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to play: $err')),
                        );
                      }
                    },
                    onDelete: () => RecentProgressService.instance.remove(id),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ===== FEATURED COLLECTIONS CAROUSEL =====
class FeaturedCollectionsCarousel extends StatelessWidget {
  const FeaturedCollectionsCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    final featured = [
      {
        'title': 'Classic Literature',
        'collection': 'gutenberg',
        'image': 'https://archive.org/services/img/gutenberg',
      },
      {
        'title': 'Vintage Comics',
        'collection': 'comics_inbox',
        'image': 'https://archive.org/services/img/comics_inbox',
      },
      {
        'title': 'Old Magazines',
        'collection': 'magazines',
        'image': 'https://archive.org/services/img/magazines',
      },
      {
        'title': 'Film Archives',
        'collection': 'movies',
        'image': 'https://archive.org/services/img/movies',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Featured Collections',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final f = featured[i];
              return _FeaturedTile(
                title: f['title']! as String,
                collection: f['collection']! as String,
                imageUrl: f['image']! as String,
              );
            },
          ),
        ),
      ],
    );
  }
}

Map<String, ({String title, IconData icon, String query})> _inAppCategories = {
  'texts': (
    title: 'Texts',
    icon: Icons.menu_book_rounded,
    query: 'mediatype:texts',
  ),
  'movies': (
    title: 'Videos',
    icon: Icons.movie_rounded,
    query: 'mediatype:movies',
  ),
  'audio': (
    title: 'Audio',
    icon: Icons.headphones_rounded,
    query: 'mediatype:audio',
  ),
  'image': (
    title: 'Images',
    icon: Icons.image_rounded,
    query: 'mediatype:image',
  ),
};

class _FeaturedTile extends StatelessWidget {
  final String title;
  final String collection;
  final String imageUrl;

  const _FeaturedTile({
    required this.title,
    required this.collection,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: title,
                  customQuery: 'collection:$collection',
                ),
          ),
        );
      },
      child: Ink(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.25),
              BlendMode.darken,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== EXPLORE BY CATEGORY =====
class ExploreByCategory extends StatelessWidget {
  const ExploreByCategory({super.key});

  Future<void> _openCategory(BuildContext context, String key) async {
    final entry = _inAppCategories[key];
    if (entry != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: entry.title,
                customQuery: entry.query,
              ),
        ),
      );
      return;
    }

    final url = 'https://archive.org/details/$key';
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${entry?.title ?? key}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final List<({String key, String title, IconData icon})> categories =
        _inAppCategories.entries
            .map((e) => (key: e.key, title: e.value.title, icon: e.value.icon))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Explore by Category',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.0,
          ),
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final cat = categories[i];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openCategory(context, cat.key),
              child: Ink(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.icon, size: 32, color: cs.primary),
                      const SizedBox(height: 8),
                      Text(
                        cat.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ===== SUPPORTING WIDGETS =====
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
