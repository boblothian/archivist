// lib/screens/home_page_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:archivereader/screens/pdf_viewer_screen.dart';
import 'package:archivereader/screens/text_viewer_screen.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/services/thumb_override_service.dart';
import 'package:archivereader/ui/shell/root_shell.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../archive_api.dart'; // <-- needed for metadata lookups
import '../media/media_player_ops.dart';
import '../utils/archive_helpers.dart';
import '../widgets/big_section_header.dart';
import 'archive_item_screen.dart';
import 'cbz_viewer_screen.dart';
import 'collection_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thumb resolver
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
  static const _pinsKey = 'pinned_collections';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadPins();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    final _ = await SharedPreferences.getInstance();
    setState(() {});
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final _ = prefs.getStringList(_pinsKey) ?? const <String>[];
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
      children: const <Widget>[
        _GlobalArchiveSearchBar(),
        SizedBox(height: 16.0),
        ExploreByCategory(),
        SizedBox(height: 24.0),
        _TopContinueColumns(),
        SizedBox(height: 24.0),
        RecommendedCollectionsSection(), // <-- NEW
        SizedBox(height: 24.0),
        FeaturedCollectionsCarousel(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Global search bar (searches all of Archive.org)
// ─────────────────────────────────────────────────────────────────────────────
class _GlobalArchiveSearchBar extends StatefulWidget {
  const _GlobalArchiveSearchBar();

  @override
  State<_GlobalArchiveSearchBar> createState() =>
      _GlobalArchiveSearchBarState();
}

class _GlobalArchiveSearchBarState extends State<_GlobalArchiveSearchBar> {
  final _ctrl = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Future<void> onSubmit() async {
      final q = _ctrl.text.trim();
      if (q.isEmpty) return;

      final phrase = q.replaceAll('"', r'\"');
      final query =
          '(title:"$phrase" OR subject:"$phrase" OR description:"$phrase" OR creator:"$phrase")';

      setState(() => _searching = true);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: 'Search',
                customQuery: query,
              ),
        ),
      );
      if (mounted) setState(() => _searching = false);
    }

    return TextField(
      controller: _ctrl,
      onSubmitted: (_) => onSubmit(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search Archive.org',
        prefixIcon: const Icon(Icons.search),

        // Fixed suffixIcon to avoid tiny overflow
        suffixIconConstraints: const BoxConstraints(
          minWidth: 72,
          maxWidth: 80,
          minHeight: 48,
        ),
        suffixIcon: SizedBox(
          width: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_searching)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () => _ctrl.clear(),
              ),
            ],
          ),
        ),

        filled: true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

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
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Big, clean thumbnail – no gradient
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10, // nice chonky thumbnail
                    child: CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder:
                          (_, __) => Container(color: Colors.grey[300]),
                      errorWidget:
                          (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 40),
                    ),
                  ),
                  if (onDelete != null)
                    Positioned(
                      top: 6,
                      right: 6,
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

              // Text + progress
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (progressLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        progressLabel!,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.75),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: cs.onSurface.withOpacity(0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Continue" strip – horizontal cards with big thumbnails
// ─────────────────────────────────────────────────────────────────────────────
class _TopContinueColumns extends StatelessWidget {
  const _TopContinueColumns();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RecentProgressService.instance.version,
      builder: (context, _, __) {
        final recent = RecentProgressService.instance.recent(limit: 30);

        if (recent.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              BigSectionHeader('Continue'),
              SizedBox(height: 8),
              Center(
                child: Text(
                  'No recent items',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BigSectionHeader('Last viewed'),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final e = recent[i];
                  final kind = _sectionKindForEntry(e);
                  return _ContinueStripCard(entry: e, kind: kind);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static bool _isReadingEntry(Map<String, dynamic> e) {
    final kind = (e['kind'] as String?)?.toLowerCase();
    final fileName = (e['fileName'] as String?)?.toLowerCase();
    const validKinds = {'pdf', 'epub', 'cbz', 'cbr', 'txt'};
    final isValidKind = kind != null && validKinds.contains(kind);
    final isTxtByFile = fileName != null && fileName.endsWith('.txt');
    return isValidKind || isTxtByFile;
  }
}

/// Map the raw "kind" field into our [_SectionKind] for reuse with resume logic.
_SectionKind _sectionKindForEntry(Map<String, dynamic> e) {
  final kind = (e['kind'] as String?)?.toLowerCase();
  if (kind == 'video') return _SectionKind.watching;
  if (kind == 'audio') return _SectionKind.listening;
  if (_TopContinueColumns._isReadingEntry(e)) return _SectionKind.reading;
  // Fallback: treat as reading
  return _SectionKind.reading;
}

class _ContinueStripCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final _SectionKind kind;

  const _ContinueStripCard({required this.entry, required this.kind});

  @override
  Widget build(BuildContext context) {
    final id = entry['id'] as String? ?? '';
    final rawTitle = (entry['title'] as String?) ?? id;
    final fileName = entry['fileName'] as String?;
    final title =
        kind == _SectionKind.reading && fileName != null
            ? _prettify(fileName)
            : rawTitle;

    final fallbackThumb = 'https://archive.org/services/img/$id';
    final initialThumb = (entry['thumb'] as String?) ?? fallbackThumb;

    // Compute progress & label (same rules as _ContinueSectionColumn)
    double percent = 0.0;
    String? label;

    if (kind == _SectionKind.watching || kind == _SectionKind.listening) {
      final positionMs = (entry['positionMs'] as int?) ?? 0;
      final durationMs = (entry['durationMs'] as int?) ?? 0;
      if (durationMs > 0 && positionMs >= 0) {
        percent = positionMs / durationMs;
      } else {
        percent = (entry['percent'] as double?) ?? 0.0;
      }
      label =
          percent > 0
              ? '${(percent * 100).toStringAsFixed(0)}% ${kind == _SectionKind.watching ? 'watched' : 'listened'}'
              : 'Tap to play';
    } else {
      if ((entry['kind'] as String?) == 'pdf') {
        final page = entry['page'] as int?;
        final total = entry['total'] as int?;
        if (page != null && total != null && total > 0) {
          percent = page / total;
          label = 'Page $page of $total';
        }
      } else {
        final p = (entry['percent'] as double?) ?? 0.0;
        percent = p;
        label = p > 0 ? '${(p * 100).toStringAsFixed(0)}%' : null;
      }
    }

    return SizedBox(
      width: 200,
      child: FutureBuilder<String>(
        future: _resolveThumb(id, initialThumb),
        initialData: initialThumb,
        builder: (context, snap) {
          final thumbToUse = snap.data ?? initialThumb;

          return _ResumeMediaCard(
            id: id,
            title: title,
            thumb: thumbToUse,
            progress: percent.clamp(0.0, 1.0),
            progressLabel: label,
            onTap:
                () => _ContinueSectionColumn.handleResumeTap(
                  context,
                  kind,
                  entry,
                ),
            onDelete: () => RecentProgressService.instance.remove(id),
          );
        },
      ),
    );
  }
}

enum _SectionKind { reading, watching, listening }

class _SectionModel {
  final String title;
  final List<Map<String, dynamic>> entries;
  final _SectionKind kind;
  _SectionModel(this.title, this.entries, this.kind);
}

class _ContinueSectionColumn extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> entries;
  final _SectionKind kind;

  const _ContinueSectionColumn({
    required this.title,
    required this.entries,
    required this.kind,
  });

  static Future<void> handleResumeTap(
    BuildContext context,
    _SectionKind kind,
    Map<String, dynamic> e,
  ) async {
    final id = e['id'] as String;
    final title = (e['title'] as String?) ?? id;
    final fileUrl = e['fileUrl'] as String?;
    final fileName = e['fileName'] as String?;
    final kindStr = (e['kind'] as String?) ?? '';
    final thumb =
        (e['thumb'] as String?) ?? 'https://archive.org/services/img/$id';

    switch (kind) {
      case _SectionKind.reading:
        if (fileUrl == null || fileName == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot resume: missing file info')),
          );
          return;
        }
        await _openResumeFile(
          context: context,
          id: id,
          title: title,
          fileUrl: fileUrl,
          fileName: fileName,
          kind: kindStr,
        );
        break;

      case _SectionKind.watching:
        if (fileUrl == null || fileName == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No video file recorded; opening item…'),
            ),
          );
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => ArchiveItemScreen(
                    title: title,
                    identifier: id,
                    files: const <Map<String, String>>[],
                    parentThumbUrl: thumb,
                  ),
            ),
          );
          return;
        }
        final positionMs = (e['positionMs'] as int?) ?? 0;
        await MediaPlayerOps.playVideo(
          context,
          url: fileUrl,
          identifier: id,
          title: title,
          startPositionMs: positionMs,
        );
        break;

      case _SectionKind.listening:
        if (fileUrl == null || fileName == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No audio file recorded; opening item…'),
            ),
          );
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => ArchiveItemScreen(
                    title: title,
                    identifier: id,
                    files: const <Map<String, String>>[],
                    parentThumbUrl: thumb,
                  ),
            ),
          );
          return;
        }
        final positionMsA = (e['positionMs'] as int?) ?? 0;
        await MediaPlayerOps.playAudio(
          context,
          url: fileUrl,
          identifier: id,
          title: title,
          startPositionMs: positionMsA,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final latest = entries.first;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap:
                  entries.length > 1
                      ? () => _showSectionSheet(
                        context,
                        title: title,
                        entries: entries,
                        kind: kind,
                      )
                      : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    Icon(
                      entries.length > 1 ? Icons.expand_more : Icons.more_horiz,
                      color:
                          entries.length > 1
                              ? null
                              : Theme.of(context).disabledColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildResumeCard(context, latest),
          ],
        ),
      ),
    );
  }

  Widget _buildResumeCard(BuildContext context, Map<String, dynamic> e) {
    final id = e['id'] as String;
    final title = (e['title'] as String?) ?? id;

    double percent = 0.0;
    String? label;

    if (kind == _SectionKind.watching || kind == _SectionKind.listening) {
      final positionMs = (e['positionMs'] as int?) ?? 0;
      final durationMs = (e['durationMs'] as int?) ?? 0;
      if (durationMs > 0 && positionMs >= 0) {
        percent = positionMs / durationMs;
      } else {
        percent = (e['percent'] as double?) ?? 0.0;
      }
      label =
          percent > 0
              ? '${(percent * 100).toStringAsFixed(0)}% ${kind == _SectionKind.watching ? 'watched' : 'listened'}'
              : 'Tap to play';
    } else {
      if ((e['kind'] as String?) == 'pdf') {
        final page = e['page'] as int?;
        final total = e['total'] as int?;
        if (page != null && total != null && total > 0) {
          percent = page / total;
          label = 'Page $page of $total';
        }
      } else {
        final p = (e['percent'] as double?) ?? 0.0;
        percent = p;
        label = p > 0 ? '${(p * 100).toStringAsFixed(0)}%' : null;
      }
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
          title:
              kind == _SectionKind.reading && (e['fileName'] as String?) != null
                  ? _prettify((e['fileName'] as String?)!)
                  : title,
          thumb: thumbToUse,
          progress: percent.clamp(0.0, 1.0),
          progressLabel: label,
          onTap: () => handleResumeTap(context, kind, e),
          onDelete: () => RecentProgressService.instance.remove(id),
        );
      },
    );
  }

  Future<void> _showSectionSheet(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> entries,
    required _SectionKind kind,
  }) async {
    final mediaH = MediaQuery.of(context).size.height;
    const tileH = 84.0;
    final desired = (entries.length * tileH) + 120;
    final maxH = mediaH * 0.85;
    final height = desired.clamp(200.0, maxH);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${entries.length} ${entries.length == 1 ? 'item' : 'items'}',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final id = e['id'] as String;
                      final t = (e['title'] as String?) ?? id;
                      final fn = e['fileName'] as String?;
                      final thumb =
                          (e['thumb'] as String?) ??
                          'https://archive.org/services/img/$id';

                      String sub = '';
                      if (kind == _SectionKind.watching ||
                          kind == _SectionKind.listening) {
                        final pos = (e['positionMs'] as int?) ?? 0;
                        final dur = (e['durationMs'] as int?) ?? 0;
                        if (dur > 0 && pos >= 0) {
                          final pct = (pos / dur).clamp(0.0, 1.0);
                          sub =
                              '${(pct * 100).toStringAsFixed(0)}% ${kind == _SectionKind.watching ? 'watched' : 'listened'}';
                        }
                      } else if ((e['kind'] as String?) == 'pdf') {
                        final page = e['page'] as int?;
                        final total = e['total'] as int?;
                        if (page != null && total != null && total > 0) {
                          sub = 'Page $page of $total';
                        }
                      }

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: thumb,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          kind == _SectionKind.reading && fn != null
                              ? _prettify(fn)
                              : t,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle:
                            sub.isNotEmpty
                                ? Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                                : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.of(sheetCtx).maybePop();
                          await handleResumeTap(context, kind, e);
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(sheetCtx).maybePop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===== CONTINUE READING helpers =====
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

// ===== Recommended Collections (NEW) =========================================
class RecommendedCollectionsSection extends StatefulWidget {
  const RecommendedCollectionsSection({super.key});

  @override
  State<RecommendedCollectionsSection> createState() =>
      _RecommendedCollectionsSectionState();
}

class _RecommendedCollectionsSectionState
    extends State<RecommendedCollectionsSection> {
  late Future<List<CollectionRec>> _future;
  late VoidCallback _versionListener;

  @override
  void initState() {
    super.initState();
    _future = _buildRecommendations();

    // When recent progress changes, recompute recommendations
    _versionListener = () {
      setState(() {
        _future = _buildRecommendations();
      });
    };
    RecentProgressService.instance.version.addListener(_versionListener);
  }

  @override
  void dispose() {
    RecentProgressService.instance.version.removeListener(_versionListener);
    super.dispose();
  }

  Future<List<CollectionRec>> _buildRecommendations() async {
    // 1) take recent items
    final recent = RecentProgressService.instance.recent(limit: 60);
    if (recent.isEmpty) return const <CollectionRec>[];

    // unique ids
    final ids = <String>{};
    for (final e in recent) {
      final id = (e['id'] as String?)?.trim();
      if (id != null && id.isNotEmpty) ids.add(id);
      if (ids.length >= 24) break; // cap to limit network calls
    }
    if (ids.isEmpty) return const <CollectionRec>[];

    // 2) fetch metadata for all ids in PARALLEL, tally collections
    final counts = <String, int>{};

    const noisy = {
      'opensource_movies',
      'opensource_audio',
      'opensource',
      'community_audio',
      'community',
      'texts',
      'movies',
      'audio',
      'image',
      'software',
    };

    // Run getMetadata for all ids at once; max 24 so this is safe.
    final metas = await Future.wait(
      ids.map((id) async {
        try {
          final meta = await ArchiveApi.getMetadata(id);
          return (id: id, meta: meta);
        } catch (_) {
          return null; // ignore failures
        }
      }),
    );

    for (final entry in metas) {
      if (entry == null) continue;
      final meta = entry.meta as Map;
      final md = Map<String, dynamic>.from(
        (meta['metadata'] as Map?) ?? const {},
      );
      final col = md['collection'];

      List<String> cols = [];
      if (col is String) {
        cols = [col];
      } else if (col is List) {
        cols = col.where((e) => e != null).map((e) => e.toString()).toList();
      }

      for (final c in cols) {
        final cid = c.trim();
        if (cid.isEmpty) continue;
        if (noisy.contains(cid.toLowerCase())) continue;
        counts[cid] = (counts[cid] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return const <CollectionRec>[];

    final top =
        counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topIds = top.take(8).map((e) => e.key).toList();

    // 3) Build recommendations WITHOUT another round of network calls.
    final recs = <CollectionRec>[];
    for (final cid in topIds) {
      final title = _prettifyCollectionId(cid); // local prettifier only
      recs.add(
        CollectionRec(
          id: cid,
          title: title,
          imageUrl: 'https://archive.org/services/img/$cid',
        ),
      );
    }

    return recs;
  }

  String _prettifyCollectionId(String id) {
    var s = id.replaceAll('_', ' ').replaceAll('-', ' ');
    s = s
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<List<CollectionRec>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data ?? const <CollectionRec>[];
        if (data.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommended for you',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: data.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final r = data[i];
                  return _FeaturedTile(
                    title: r.title,
                    collection: r.id,
                    imageUrl: r.imageUrl,
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

class CollectionRec {
  final String id;
  final String title;
  final String imageUrl;
  const CollectionRec({
    required this.id,
    required this.title,
    required this.imageUrl,
  });
}

// ===== Featured + Categories =====
class ExploreByCategory extends StatelessWidget {
  const ExploreByCategory({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final categories =
        _inAppCategories.entries
            .map((e) => (key: e.key, title: e.value.title, icon: e.value.icon))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Explore by Category',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = categories[i];
              // Stadium pill for each category
              return IntrinsicWidth(
                child: Material(
                  color: cs.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => _openCategory(context, c.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      // Wrap Row in FittedBox so it can shrink
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(c.icon, size: 18, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

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
}

class FeaturedCollectionsCarousel extends StatelessWidget {
  const FeaturedCollectionsCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    final featured = [
      {
        'title': 'Internet Archive Books',
        'collection': 'internetarchivebooks',
        'image': 'https://archive.org/services/img/internetarchivebooks',
      },
      {
        'title': 'Magazines',
        'collection': 'magazines',
        'image': 'https://archive.org/services/img/magazines',
      },
      {
        'title': 'Film Archives',
        'collection': 'movies',
        'image': 'https://archive.org/services/img/movies',
      },
      {
        'title': 'Classic TV',
        'collection': 'classic_tv',
        'image': 'https://archive.org/services/img/classic_tv',
      },
      {
        'title': 'Old Time Radio',
        'collection': 'oldtimeradio',
        'image': 'https://archive.org/services/img/oldtimeradio',
      },
      {
        'title': 'Comics',
        'collection': 'comics_inbox',
        'image': 'https://archive.org/services/img/comics_inbox',
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
                title: f['title']!,
                collection: f['collection']!,
                imageUrl: f['image']!,
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
