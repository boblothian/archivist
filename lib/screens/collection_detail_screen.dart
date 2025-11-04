// collection_detail_screen.dart
import 'dart:convert';

import 'package:animations/animations.dart'; // <-- NEW
import 'package:archivereader/screens/video_player_screen.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/services/thumb_override_service.dart';
import 'package:archivereader/services/thumbnail_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:archivereader/widgets/favourite_add_dialogue.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'; // for compute()
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../net.dart';
import '../utils/archive_helpers.dart';
import '../utils/external_launch.dart';
import 'archive_item_screen.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'text_viewer_screen.dart';

// TOP-LEVEL ENUM — MUST BE HERE
enum DialogResult { addToFolder, generateThumb }

const Map<String, String> _HEADERS = Net.headers;

enum SortMode {
  popularAllTime,
  popularMonth,
  popularWeek,
  newest,
  oldest,
  alphaAZ,
  alphaZA,
}

enum SearchScope { metadata, title }

enum ViewMode { grid, list }

const int _QUICK_PICK_LIMIT = 24;
const int _CHILD_ROWS = 36; // lower for faster quick pick

String _sortParam(SortMode m) {
  switch (m) {
    case SortMode.popularAllTime:
      return 'downloads desc';
    case SortMode.popularMonth:
      return 'month desc';
    case SortMode.popularWeek:
      return 'week desc';
    case SortMode.newest:
      return 'date desc';
    case SortMode.oldest:
      return 'date asc';
    case SortMode.alphaAZ:
      return 'titleSorter asc';
    case SortMode.alphaZA:
      return 'titleSorter desc';
  }
}

class _SfwFilter {
  static final List<RegExp> _bad = <RegExp>[
    RegExp(r'\bnsfw\b', caseSensitive: false),
    RegExp(r'\bexplicit\b', caseSensitive: false),
    RegExp(r'\bporn\b', caseSensitive: false),
    RegExp(r'\badult\b', caseSensitive: false),
    RegExp(r'\bhentai\b', caseSensitive: false),
    RegExp(r'\bxxx\b', caseSensitive: false),
  ];
  static bool isClean(Map<String, String> m) {
    final hay =
        '${m['title'] ?? ''} ${m['subject'] ?? ''} ${m['description'] ?? ''}';
    return !_bad.any((r) => r.hasMatch(hay));
  }

  static String serverExclusionSuffix() => '';
}

class CollectionDetailScreen extends StatefulWidget {
  final String categoryName;
  final String? collectionName;
  final String? customQuery;
  final dynamic filters;

  const CollectionDetailScreen({
    super.key,
    required this.categoryName,
    this.collectionName,
    this.customQuery,
    this.filters,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Single reusable HTTP client + timeout
  static final http.Client _client = http.Client();
  static const Duration _netTimeout = Duration(seconds: 12);

  final List<Map<String, String>> _items = <Map<String, String>>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _requestToken = 0;
  static const int _rows = 60; // smaller first-page for snappier paint
  int _page = 1;
  int _numFound = 0;

  bool get _hasMore => _items.length < _numFound;

  SortMode _sort = SortMode.popularAllTime;
  SearchScope _searchScope = SearchScope.metadata;
  ViewMode _viewMode = ViewMode.grid;

  late bool _sfwOnly = _tryFlag(widget.filters, 'sfwOnly', false);
  late bool _favouritesOnly = _tryFlag(widget.filters, 'favouritesOnly', false);
  late bool _downloadedOnly = _tryFlag(widget.filters, 'downloadedOnly', false);

  bool _showScrollTop = false;
  bool _isDisposed = false;

  // ---------- NEW: shared axis route helper ----------
  Route<T> _sharedAxisRoute<T>(
    Widget page, {
    SharedAxisTransitionType type = SharedAxisTransitionType.scaled,
  }) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: type,
          child: child,
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _init();
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 400;
      if (show != _showScrollTop && mounted) {
        setState(() => _showScrollTop = show);
      }
    });
  }

  static bool _tryFlag(dynamic obj, String name, bool def) {
    if (obj == null) return def;
    try {
      final json = (obj as dynamic).toJson();
      final v = json[name];
      if (v is bool) return v;
    } catch (_) {}
    if (obj is Map) {
      final v = obj[name];
      if (v is bool) return v;
    }
    return def;
  }

  Future<void> _init() async {
    await _fetch(reset: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _dismissKeyboard();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && !focus.hasPrimaryFocus) {
      focus.unfocus();
    }
  }

  String _prettyFilename(String raw) {
    var s = raw;
    s = s.replaceFirst(
      RegExp(r'\.(mp4|mkv|webm|pdf|epub|cbz|cbr|txt)$', caseSensitive: false),
      '',
    );
    s = s.replaceFirst(RegExp(r'\.ia$', caseSensitive: false), '');
    s = s.replaceAll('_', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String _humanBytes(int? b) {
    if (b == null || b <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = b.toDouble();
    int u = 0;
    while (size >= 1024 && u < units.length - 1) {
      size /= 1024;
      u++;
    }
    return u == 0
        ? '$b ${units[u]}'
        : '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[u]}';
  }

  String _buildQuery(String searchQuery) {
    final String baseQuery =
        (widget.customQuery != null && widget.customQuery!.trim().isNotEmpty)
            ? widget.customQuery!.trim()
            : 'collection:${widget.collectionName}';

    final fields =
        _searchScope == SearchScope.metadata
            ? <String>['title', 'subject', 'description', 'creator']
            : <String>['title'];

    String full = baseQuery;
    if (searchQuery.isNotEmpty) {
      final phrase = searchQuery.replaceAll('"', r'\"');
      final orClause = fields.map((f) => '$f:"$phrase"').join(' OR ');
      full = '($baseQuery) AND ($orClause)';
    }
    if (_sfwOnly) full = '($full)${_SfwFilter.serverExclusionSuffix()}';
    return full;
  }

  // Parse JSON off the UI thread
  Future<Map<String, dynamic>> _decodeJson(String body) async {
    return compute((String s) => jsonDecode(s) as Map<String, dynamic>, body);
  }

  // Background smart-thumb upgrader (bounded concurrency) respecting user overrides
  /// Background smart-thumb upgrader (bounded concurrency) respecting user overrides
  Future<void> _unblockSmartThumbs(
    List<Map<String, String>> batch, {
    required int currentToken,
  }) async {
    const int kMaxConcurrent = 6;

    // Collect all changes in memory first
    final Map<int, String> thumbUpdates = {};

    // Helper: process one item
    Future<void> _process(Map<String, String> item) async {
      try {
        if (!mounted || _isDisposed || currentToken != _requestToken) return;

        final id = item['identifier']!;
        final mediatype = item['mediatype'] ?? '';
        final title = item['title'] ?? id;
        final year = item['year'] ?? '';

        // Skip if already upgraded or overridden
        final currentThumb = (item['thumb'] ?? '').trim();
        final placeholder = archiveThumbUrl(id);
        if (currentThumb.isNotEmpty && currentThumb != placeholder) {
          return;
        }

        final smart = await ThumbnailService().getSmartThumb(
          id: id,
          mediatype: mediatype,
          title: title,
          year: year,
        );

        if (!mounted || _isDisposed || currentToken != _requestToken) return;
        if (smart.isEmpty || smart == currentThumb) return;

        // Find index in _items
        final idx = _items.indexWhere((e) => e['identifier'] == id);
        if (idx != -1) {
          thumbUpdates[idx] = smart;
        }
      } catch (_) {
        // Ignore per-item failures
      }
    }

    // Process in chunks to bound concurrency
    for (int i = 0; i < batch.length; i += kMaxConcurrent) {
      if (!mounted || _isDisposed || currentToken != _requestToken) {
        return;
      }

      final end = (i + kMaxConcurrent).clamp(0, batch.length);
      final slice = batch.sublist(i, end);

      await Future.wait(slice.map(_process));
    }

    // === SINGLE setState UPDATE ===
    if (thumbUpdates.isNotEmpty &&
        mounted &&
        !_isDisposed &&
        currentToken == _requestToken) {
      setState(() {
        thumbUpdates.forEach((idx, smartThumb) {
          _items[idx] = Map<String, String>.from(_items[idx])
            ..['thumb'] = smartThumb;
        });
      });
    }
  }

  Future<void> _fetch({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _numFound = 0;
      _items.clear();
      _error = null;
      if (mounted) setState(() => _loading = true);
    } else {
      if (mounted) setState(() => _loadingMore = true);
    }

    if ((widget.collectionName == null ||
            widget.collectionName!.trim().isEmpty) &&
        (widget.customQuery == null || widget.customQuery!.trim().isEmpty)) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = 'No collection or custom query provided.';
        });
      }
      return;
    }

    final int token = ++_requestToken;
    final q = _buildQuery(_searchCtrl.text.trim());

    final flParams = <String>[
      'identifier',
      'title',
      'mediatype',
      'subject',
      'creator',
      'description',
      'year',
    ].map((f) => 'fl[]=$f').join('&');

    final url =
        'https://archive.org/advancedsearch.php?'
        'q=${Uri.encodeQueryComponent(q)}&'
        '$flParams&sort[]=${Uri.encodeQueryComponent(_sortParam(_sort))}&'
        'rows=$_rows&page=$_page&output=json';

    try {
      final resp = await _client
          .get(Uri.parse(url), headers: _HEADERS)
          .timeout(_netTimeout);

      if (!mounted || _isDisposed || token != _requestToken) return;

      if (resp.statusCode != 200) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingMore = false;
            _error = 'Search failed (${resp.statusCode}).';
          });
        }
        return;
      }

      final data = await _decodeJson(resp.body);
      final response = (data['response'] as Map<String, dynamic>?) ?? const {};
      final List docs = (response['docs'] as List?) ?? const [];
      _numFound =
          (response['numFound'] as int?) ??
          (_numFound == 0 ? docs.length : _numFound);

      String flat(dynamic v) {
        if (v == null) return '';
        if (v is List) {
          return v.whereType<Object>().map((e) => e.toString()).join(', ');
        }
        return v.toString();
      }

      // Fast batch (placeholder thumbs)
      List<Map<String, String>> batch = [];
      for (final doc in docs) {
        final id = (doc['identifier'] ?? '').toString();
        final rawTitle = flat(doc['title']).trim();
        final title = rawTitle.isEmpty ? id : rawTitle;
        final year = flat(doc['year']);
        final mediatype = flat(doc['mediatype']);
        final thumb = archiveThumbUrl(id);

        batch.add({
          'identifier': id,
          'title': title,
          'thumb': thumb,
          'mediatype': mediatype,
          'description': flat(doc['description']),
          'creator': flat(doc['creator']),
          'subject': flat(doc['subject']),
          'year': year,
        });
      }

      // Filters
      if (_sfwOnly) {
        final filtered = batch.where(_SfwFilter.isClean).toList();
        if (filtered.isNotEmpty || _searchCtrl.text.trim().isNotEmpty) {
          batch = filtered;
        }
      }
      if (_favouritesOnly) {
        final favs =
            FavoritesService.instance.allItems.map((e) => e.id).toSet();
        batch = batch.where((m) => favs.contains(m['identifier'])).toList();
      }

      // Apply overrides before render
      await ThumbOverrideService.instance.applyToItemMaps(batch);

      // De-dup against existing
      final existingIds = _items.map((m) => m['identifier']).toSet();
      batch =
          batch
              .where(
                (m) =>
                    m['identifier'] != null &&
                    !existingIds.contains(m['identifier'] ?? ''),
              )
              .toList();

      // Render immediately
      if (mounted && !_isDisposed) {
        setState(() {
          _items.addAll(batch);
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
      }

      // Upgrade thumbs in background
      _unblockSmartThumbs(batch, currentToken: token);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = 'Network error. Please try again.';
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    await _fetch(reset: true);
  }

  void _runSearch() => _fetch(reset: true);

  // ─────────────────────────────────────────────────────────────────────────────
  //  LONG-PRESS MENU – TMDb thumbnail + add-to-favourites + enrich metadata
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _handleLongPressItem(Map<String, String> item) async {
    if (_isDisposed) return;

    HapticFeedback.mediumImpact();
    _dismissKeyboard();

    final messenger = ScaffoldMessenger.maybeOf(context);
    final id = item['identifier']!;
    final title = item['title'] ?? id;
    final mediatype = item['mediatype'] ?? '';
    final year = item['year'] ?? '';

    final fav = FavoriteItem(
      id: id,
      title: title,
      url: 'https://archive.org/details/$id',
      thumb: item['thumb']!,
    );

    final svc = FavoritesService.instance;
    if (svc.folders().isEmpty) {
      await svc.createFolder('Favourites');
    }

    final titleCtrl = TextEditingController(text: title);
    bool isSearching = false;
    bool enrichEnabled = false; // local toggle

    final result = await showDialog<DialogResult>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Options'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Add to Favourites
                        ListTile(
                          leading: const Icon(Icons.favorite_border),
                          title: const Text('Add to Favourites'),
                          subtitle: Text('Add "$title" to a folder'),
                          onTap:
                              () =>
                                  Navigator.pop(ctx, DialogResult.addToFolder),
                        ),

                        const Divider(height: 16),

                        // Enrich Metadata Toggle
                        SwitchListTile(
                          value: enrichEnabled,
                          onChanged: (v) async {
                            setDialogState(() => enrichEnabled = v);
                            if (v) {
                              final updated = Map<String, String>.from(item);
                              try {
                                await ThumbnailService().enrichItemWithTmdb(
                                  updated,
                                );

                                final idx = _items.indexWhere(
                                  (i) => i['identifier'] == id,
                                );
                                if (idx != -1 && mounted && !_isDisposed) {
                                  setState(() => _items[idx] = updated);
                                }

                                messenger?.showSnackBar(
                                  const SnackBar(
                                    content: Text('Metadata enriched!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (_) {
                                messenger?.showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to enrich metadata'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          title: const Text('Enrich Metadata'),
                          subtitle: const Text(
                            'Pull title, year, description, and poster from TMDb',
                          ),
                        ),

                        const Divider(height: 16),

                        // TMDb Thumbnail Generator (Video/Movies only)
                        if (mediatype.toLowerCase().contains('video') ||
                            mediatype == 'movies')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Generate Thumbnail from TMDb',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: titleCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Enter movie/TV title',
                                  border: const OutlineInputBorder(),
                                  suffixIcon:
                                      isSearching
                                          ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                          : IconButton(
                                            icon: const Icon(Icons.search),
                                            onPressed:
                                                isSearching
                                                    ? null
                                                    : () async {
                                                      final query =
                                                          titleCtrl.text.trim();
                                                      if (query.isEmpty) {
                                                        messenger?.showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Please enter a title',
                                                            ),
                                                            backgroundColor:
                                                                Colors.orange,
                                                          ),
                                                        );
                                                        return;
                                                      }

                                                      setDialogState(
                                                        () =>
                                                            isSearching = true,
                                                      );

                                                      try {
                                                        final chosen =
                                                            await ThumbnailService()
                                                                .choosePosterRich(
                                                                  ctx,
                                                                  query,
                                                                  year:
                                                                      year.isNotEmpty
                                                                          ? year
                                                                          : null,
                                                                  currentTitle:
                                                                      title,
                                                                );

                                                        if (chosen == null)
                                                          return;

                                                        await FavoritesService
                                                            .instance
                                                            .updateThumbForId(
                                                              id,
                                                              chosen,
                                                            );

                                                        final idx = _items
                                                            .indexWhere(
                                                              (i) =>
                                                                  i['identifier'] ==
                                                                  id,
                                                            );
                                                        if (idx != -1 &&
                                                            mounted &&
                                                            !_isDisposed) {
                                                          setState(
                                                            () =>
                                                                _items[idx]['thumb'] =
                                                                    chosen,
                                                          );
                                                        }

                                                        await ThumbOverrideService
                                                            .instance
                                                            .set(id, chosen);

                                                        messenger?.showSnackBar(
                                                          SnackBar(
                                                            content: const Text(
                                                              'Thumbnail updated!',
                                                            ),
                                                            backgroundColor:
                                                                Colors.green,
                                                            action: SnackBarAction(
                                                              label: 'View',
                                                              onPressed:
                                                                  () => launchUrl(
                                                                    Uri.parse(
                                                                      chosen,
                                                                    ),
                                                                  ),
                                                            ),
                                                          ),
                                                        );

                                                        if (ctx.mounted) {
                                                          Navigator.pop(
                                                            ctx,
                                                            DialogResult
                                                                .generateThumb,
                                                          );
                                                        }
                                                      } catch (e) {
                                                        messenger?.showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              'Search failed: $e',
                                                            ),
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                        );
                                                      } finally {
                                                        if (ctx.mounted) {
                                                          setDialogState(
                                                            () =>
                                                                isSearching =
                                                                    false,
                                                          );
                                                        }
                                                      }
                                                    },
                                          ),
                                ),
                              ),
                              if (year.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Year: $year',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
          ),
    );

    titleCtrl.dispose();

    if (result == DialogResult.addToFolder && context.mounted && !_isDisposed) {
      final folder = await showAddToFavoritesDialog(context, item: fav);
      if (folder != null) {
        await svc.addToFolder(folder, fav);
      }
    }
  }

  Future<void> _openItem(Map<String, String> item) async {
    if (_isDisposed) return;
    final id = item['identifier']!;
    HapticFeedback.selectionClick();
    _dismissKeyboard();

    try {
      final resp = await _client
          .get(Uri.parse('https://archive.org/metadata/$id'), headers: _HEADERS)
          .timeout(_netTimeout);
      if (!mounted || _isDisposed) return;

      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load metadata (${resp.statusCode}).'),
          ),
        );
        return;
      }

      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      final mediatype = m['metadata']?['mediatype']?.toString().toLowerCase();

      if (mediatype == 'collection') {
        await _openCollectionSmart(id, item['title'] ?? id);
        return;
      }

      // ──────────────────────── TEXTS FALLBACK CHAIN ────────────────────────
      if (mediatype == 'texts') {
        final rawFiles = (m['files'] as List?) ?? const <dynamic>[];

        // 1. PDFs
        final pdfFiles =
            rawFiles.cast<Map<String, dynamic>>().where((f) {
              final name = (f['name'] ?? '').toString().toLowerCase();
              final fmt = (f['format'] ?? '').toString().toLowerCase();
              return name.endsWith('.pdf') || fmt.contains('pdf');
            }).toList();

        if (pdfFiles.isNotEmpty) {
          if (pdfFiles.length == 1) {
            final pdf = pdfFiles.first;
            final name = pdf['name'] as String;
            final fileUrl =
                'https://archive.org/download/$id/${Uri.encodeComponent(name)}';

            await RecentProgressService.instance.touch(
              id: id,
              title: item['title'] ?? id,
              thumb: archiveThumbUrl(id),
              kind: 'pdf',
              fileUrl: fileUrl,
              fileName: name,
            );

            if (!mounted || _isDisposed) return;

            Navigator.of(context).push(
              _sharedAxisRoute(
                PdfViewerScreen(
                  url: fileUrl,
                  filenameHint: name,
                  identifier: id,
                  title: item['title'] ?? id,
                ),
              ),
            );
            return;
          }

          final pdfList =
              pdfFiles
                  .map((f) => {'name': f['name'] as String})
                  .cast<Map<String, String>>()
                  .toList();

          if (!mounted || _isDisposed) return;
          Navigator.of(context).push(
            _sharedAxisRoute(
              ArchiveItemScreen(
                title: item['title'] ?? id,
                identifier: id,
                files: pdfList,
              ),
            ),
          );
          return;
        }

        // 2. Images
        final imageFiles =
            rawFiles.cast<Map<String, dynamic>>().where((f) {
              final name = (f['name'] ?? '').toString().toLowerCase();
              final fmt = (f['format'] ?? '').toString().toLowerCase();
              return name.endsWith('.jpg') ||
                  name.endsWith('.jpeg') ||
                  name.endsWith('.png') ||
                  name.endsWith('.gif') ||
                  name.endsWith('.webp') ||
                  fmt.contains('jpeg') ||
                  fmt.contains('png') ||
                  fmt.contains('gif') ||
                  fmt.contains('webp');
            }).toList();

        if (imageFiles.isNotEmpty) {
          final imageUrls =
              imageFiles
                  .map(
                    (f) =>
                        'https://archive.org/download/$id/${Uri.encodeComponent(f['name'] as String)}',
                  )
                  .toList();

          await RecentProgressService.instance.touch(
            id: id,
            title: item['title'] ?? id,
            thumb: archiveThumbUrl(id),
            kind: 'image',
          );

          if (!mounted || _isDisposed) return;

          Navigator.of(
            context,
          ).push(_sharedAxisRoute(ImageViewerScreen(imageUrls: imageUrls)));
          return;
        }

        // 3. Plain text
        final textFiles =
            rawFiles.cast<Map<String, dynamic>>().where((f) {
              final name = (f['name'] ?? '').toString().toLowerCase();
              final fmt = (f['format'] ?? '').toString().toLowerCase();
              return name.endsWith('.txt') ||
                  name.endsWith('.md') ||
                  name.endsWith('.log') ||
                  name.endsWith('.csv') ||
                  fmt.contains('text') ||
                  fmt.contains('plain');
            }).toList();

        if (textFiles.isNotEmpty) {
          final txt = textFiles.first;
          final name = txt['name'] as String;
          final fileUrl =
              'https://archive.org/download/$id/${Uri.encodeComponent(name)}';

          await RecentProgressService.instance.touch(
            id: id,
            title: item['title'] ?? id,
            thumb: archiveThumbUrl(id),
            kind: 'text',
            fileUrl: fileUrl,
            fileName: name,
          );

          if (!mounted || _isDisposed) return;

          Navigator.of(context).push(
            _sharedAxisRoute(
              TextViewerScreen(
                url: fileUrl,
                filenameHint: name,
                identifier: id,
                title: item['title'] ?? id,
              ),
            ),
          );
          return;
        }

        // 4. Fallback: generic file list (for texts)
        final justNames =
            rawFiles
                .whereType<Map>()
                .where((f) => (f['name'] as String?)?.isNotEmpty == true)
                .map<Map<String, String>>((f) => {'name': f['name'] as String})
                .toList();

        if (justNames.isEmpty) {
          final ok = await launchUrl(
            Uri.parse('https://archive.org/details/$id'),
            mode: LaunchMode.externalApplication,
          );
          if (!ok && mounted && !_isDisposed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No files found and cannot open on web.'),
              ),
            );
          }
          return;
        }

        if (!mounted || _isDisposed) return;
        Navigator.of(context).push(
          _sharedAxisRoute(
            ArchiveItemScreen(
              title: item['title'] ?? id,
              identifier: id,
              files: justNames,
            ),
          ),
        );
        return;
      }

      // ──────────────────────── AUDIO DETECTION (mediatype: audio) ────────────────────────
      if (mediatype == 'audio') {
        final rawFiles = (m['files'] as List?) ?? const <dynamic>[];
        final audioFiles = <Map<String, dynamic>>[];

        for (final f in rawFiles) {
          if (f is! Map) continue;
          final name = (f['name'] ?? '').toString();
          if (name.isEmpty) continue;
          final fmt = (f['format'] ?? '').toString().toLowerCase();
          final lower = name.toLowerCase();

          final isAudio =
              fmt.contains('mp3') ||
              fmt.contains('ogg') ||
              fmt.contains('flac') ||
              fmt.contains('wav') ||
              fmt.contains('audio') ||
              lower.endsWith('.mp3') ||
              lower.endsWith('.ogg') ||
              lower.endsWith('.oga') ||
              lower.endsWith('.flac') ||
              lower.endsWith('.wav') ||
              lower.endsWith('.aac') ||
              lower.endsWith('.m4a');

          if (isAudio) {
            audioFiles.add({'name': name, 'format': fmt, 'size': f['size']});
          }
        }

        if (audioFiles.isNotEmpty) {
          final audioList =
              audioFiles
                  .map<Map<String, String>>(
                    (f) => {'name': f['name'] as String},
                  )
                  .toList();

          await RecentProgressService.instance.touch(
            id: id,
            title: item['title'] ?? id,
            thumb: archiveThumbUrl(id),
            kind: 'audio',
          );

          if (!mounted || _isDisposed) return;

          Navigator.of(context).push(
            _sharedAxisRoute(
              ArchiveItemScreen(
                title: item['title'] ?? id,
                identifier: id,
                files: audioList,
                parentThumbUrl: item['thumb'],
              ),
            ),
          );
          return;
        }
      }

      // ──────────────────────── VIDEO DETECTION ────────────────────────
      final rawFiles = (m['files'] as List?) ?? const <dynamic>[];
      final videoFiles = <Map<String, dynamic>>[];
      for (final f in rawFiles) {
        if (f is! Map) continue;
        final name = (f['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final fmt = (f['format'] ?? '').toString().toLowerCase();
        final lower = name.toLowerCase();

        final isVideo =
            fmt.contains('mp4') ||
            fmt.contains('mpeg4') ||
            fmt.contains('h.264') ||
            fmt.contains('matroska') ||
            fmt.contains('webm') ||
            lower.endsWith('.mp4') ||
            lower.endsWith('.m4v') ||
            lower.endsWith('.mkv') ||
            lower.endsWith('.webm') ||
            lower.endsWith('.m3u8');

        if (isVideo) {
          videoFiles.add({
            'name': name,
            'format': fmt,
            'isVideo': true,
            'size': f['size'],
          });
        }
      }

      if (videoFiles.isNotEmpty) {
        if (!mounted || _isDisposed) return;
        _dismissKeyboard();
        await _openVideoChooser(context, id, item['title'] ?? id, videoFiles);
        return;
      }

      // ──────────────────────── GENERIC FALLBACK (any other mediatype) ────────────────────────
      final justNames =
          rawFiles
              .whereType<Map>()
              .where((f) => (f['name'] as String?)?.isNotEmpty == true)
              .map<Map<String, String>>((f) => {'name': f['name'] as String})
              .toList();

      if (justNames.isEmpty) {
        final ok = await launchUrl(
          Uri.parse('https://archive.org/details/$id'),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No files found and cannot open on web.'),
            ),
          );
        }
        return;
      }

      if (!mounted || _isDisposed) return;
      Navigator.of(context).push(
        _sharedAxisRoute(
          ArchiveItemScreen(
            title: item['title'] ?? id,
            identifier: id,
            files: justNames,
          ),
        ),
      );
    } catch (_) {
      if (!mounted || _isDisposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open item (network).')),
      );
    }
  }

  Future<void> _openCollectionSmart(String collectionId, String title) async {
    final children = await _fetchCollectionChildren(
      collectionId,
      enrich: false,
    );
    if (!mounted || _isDisposed) return;

    if (children.isEmpty) {
      Navigator.of(context).push(
        _sharedAxisRoute(
          CollectionDetailScreen(
            categoryName: title,
            collectionName: collectionId,
            filters: {
              'sfwOnly': _sfwOnly,
              'favouritesOnly': _favouritesOnly,
              'downloadedOnly': _downloadedOnly,
            },
          ),
        ),
      );
      return;
    }

    if (children.length <= _QUICK_PICK_LIMIT) {
      final selected = await showModalBottomSheet<Map<String, String>>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder:
            (_) => _CollectionQuickPick(
              title: title,
              items: children,
              onSeeAll: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  _sharedAxisRoute(
                    CollectionDetailScreen(
                      categoryName: title,
                      collectionName: collectionId,
                      filters: {
                        'sfwOnly': _sfwOnly,
                        'favouritesOnly': _favouritesOnly,
                        'downloadedOnly': _downloadedOnly,
                      },
                    ),
                  ),
                );
              },
            ),
      );
      if (selected != null) {
        await _openItem(selected);
      }
      return;
    }

    Navigator.of(context).push(
      _sharedAxisRoute(
        CollectionDetailScreen(
          categoryName: title,
          collectionName: collectionId,
          filters: {
            'sfwOnly': _sfwOnly,
            'favouritesOnly': _favouritesOnly,
            'downloadedOnly': _downloadedOnly,
          },
        ),
      ),
    );
  }

  Future<List<Map<String, String>>> _fetchCollectionChildren(
    String collectionId, {
    bool enrich = false,
  }) async {
    final q = 'collection:$collectionId';
    final flParams = <String>[
      'identifier',
      'title',
      'mediatype',
      'subject',
      'creator',
      'description',
      'year',
    ].map((f) => 'fl[]=$f').join('&');

    final url =
        'https://archive.org/advancedsearch.php?'
        'q=${Uri.encodeQueryComponent(q)}&'
        '$flParams&sort[]=${Uri.encodeQueryComponent('downloads desc')}&'
        'rows=$_CHILD_ROWS&page=1&output=json';

    try {
      final resp = await _client
          .get(Uri.parse(url), headers: _HEADERS)
          .timeout(_netTimeout);
      if (resp.statusCode != 200) return const <Map<String, String>>[];

      final data = await _decodeJson(resp.body);
      final List docs = (data['response']?['docs'] as List?) ?? const [];

      String flat(dynamic v) {
        if (v == null) return '';
        if (v is List) {
          return v.whereType<Object>().map((e) => e.toString()).join(', ');
        }
        return v.toString();
      }

      List<Map<String, String>> items =
          docs.map<Map<String, String>>((doc) {
            final id = (doc['identifier'] ?? '').toString();
            final title = flat(doc['title']).trim();
            final year = flat(doc['year']);
            return {
              'identifier': id,
              'title': title.isEmpty ? id : title,
              'thumb': archiveThumbUrl(id),
              'mediatype': flat(doc['mediatype']),
              'description': flat(doc['description']),
              'creator': flat(doc['creator']),
              'subject': flat(doc['subject']),
              'year': year,
            };
          }).toList();

      if (_sfwOnly) items = items.where(_SfwFilter.isClean).toList();
      if (_favouritesOnly) {
        final favs =
            FavoritesService.instance.allItems.map((e) => e.id).toSet();
        items = items.where((m) => favs.contains(m['identifier'])).toList();
      }

      await ThumbOverrideService.instance.applyToItemMaps(items);

      final seen = <String>{};
      items =
          items.where((m) {
            final id = m['identifier'] ?? '';
            if (id.isEmpty || seen.contains(id)) return false;
            seen.add(id);
            return true;
          }).toList();

      return items;
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  void _openSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SortTile(
                  'Most popular — all time',
                  SortMode.popularAllTime,
                  _sort,
                  _selectSort,
                ),
                _SortTile(
                  'Most popular — last month',
                  SortMode.popularMonth,
                  _sort,
                  _selectSort,
                ),
                _SortTile(
                  'Most popular — last week',
                  SortMode.popularWeek,
                  _sort,
                  _selectSort,
                ),
                const Divider(height: 1),
                _SortTile('Newest', SortMode.newest, _sort, _selectSort),
                _SortTile('Oldest', SortMode.oldest, _sort, _selectSort),
                const Divider(height: 1),
                _SortTile('A–Z', SortMode.alphaAZ, _sort, _selectSort),
                _SortTile('Z–A', SortMode.alphaZA, _sort, _selectSort),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _selectSort(SortMode m) {
    Navigator.of(context).maybePop();
    if (_sort != m) {
      setState(() => _sort = m);
      _fetch(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Text(widget.categoryName),
        actions: [
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onPressed: _openSortSheet,
          ),
          IconButton(
            tooltip: _viewMode == ViewMode.grid ? 'List view' : 'Grid view',
            icon: Icon(
              _viewMode == ViewMode.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed:
                () => setState(
                  () =>
                      _viewMode =
                          _viewMode == ViewMode.grid
                              ? ViewMode.list
                              : ViewMode.grid,
                ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('collection_search_field'),
                    controller: _searchCtrl,
                    enabled: !_isDisposed,
                    onSubmitted: (_) => _runSearch(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search in ${widget.categoryName}',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          _runSearch();
                        },
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SearchScope>(
                      value: _searchScope,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _searchScope = value);
                        _runSearch();
                      },
                      items: const [
                        DropdownMenuItem(
                          value: SearchScope.metadata,
                          child: Text('Metadata'),
                        ),
                        DropdownMenuItem(
                          value: SearchScope.title,
                          child: Text('Title'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildChips(cs),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: _buildBody(cs),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          (!_loading && _hasMore)
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed:
                          _loadingMore
                              ? null
                              : () {
                                _page += 1;
                                _fetch(reset: false);
                              },
                      icon:
                          _loadingMore
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.unfold_more),
                      label: Text(_loadingMore ? 'Loading…' : 'Load more'),
                    ),
                  ),
                ),
              )
              : null,
      floatingActionButton:
          _showScrollTop
              ? FloatingActionButton(
                tooltip: 'Scroll to top',
                onPressed:
                    () => _scrollCtrl.animateTo(
                      0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                    ),
                child: const Icon(Icons.arrow_upward),
              )
              : null,
    );
  }

  Widget _buildChips(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: -6,
        children: [
          FilterChip(
            label: const Text('SFW'),
            selected: _sfwOnly,
            onSelected: (v) {
              setState(() => _sfwOnly = v);
              _fetch(reset: true);
            },
          ),
          if (_numFound > 0)
            InputChip(label: Text('Found $_numFound'), onPressed: null),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const _CenteredSpinner(label: 'Loading…');
    }
    if (_error != null) {
      return _ErrorPane(
        message: _error!,
        onRetry: () => _fetch(reset: true),
        onOpenWeb:
            (widget.collectionName != null)
                ? () {
                  final base =
                      (widget.customQuery != null &&
                              widget.customQuery!.trim().isNotEmpty)
                          ? widget.customQuery!.trim()
                          : 'collection:${widget.collectionName}';
                  final url = Uri.parse(
                    'https://archive.org/advancedsearch.php?q=${Uri.encodeQueryComponent(base)}&rows=50&page=1&output=json',
                  );
                  launchUrl(url, mode: LaunchMode.externalApplication);
                }
                : null,
      );
    }
    if (_items.isEmpty) {
      return _EmptyPane(
        title: 'No items found',
        subtitle: 'Try a broader search or change filters.',
        onRefresh: () => _fetch(reset: true),
        onOpenWeb:
            (widget.collectionName != null)
                ? () {
                  final base =
                      (widget.customQuery != null &&
                              widget.customQuery!.trim().isNotEmpty)
                          ? widget.customQuery!.trim()
                          : 'collection:${widget.collectionName}';
                  final url = Uri.parse(
                    'https://archive.org/advancedsearch.php?q=${Uri.encodeQueryComponent(base)}&rows=50&page=1&output=json',
                  );
                  launchUrl(url, mode: LaunchMode.externalApplication);
                }
                : null,
      );
    }

    // ---------- NEW: animate grid <-> list ----------
    final Widget view =
        (_viewMode == ViewMode.list)
            ? ListView.builder(
              key: const ValueKey('list'),
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final it = _items[index];
                return _ListTileCard(
                  id: it['identifier']!,
                  title: it['title']!,
                  subtitle:
                      it['creator']?.isNotEmpty == true
                          ? it['creator']!
                          : it['subject'] ?? '',
                  mediatype: it['mediatype'] ?? '',
                  year: it['year'],
                  thumb: it['thumb'],
                  onTap: () => _openItem(it),
                  onLongPress: () => _handleLongPressItem(it),
                );
              },
            )
            : LayoutBuilder(
              key: const ValueKey('grid'),
              builder: (context, c) {
                final cross = adaptiveCrossAxisCount(c.maxWidth);
                return GridView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final it = _items[index];
                    final isCollection =
                        (it['mediatype'] ?? '').toLowerCase() == 'collection';
                    return _GridCard(
                      id: it['identifier']!,
                      title: it['title']!,
                      mediatype: it['mediatype'] ?? '',
                      year: it['year'],
                      thumb: it['thumb'],
                      highlight: isCollection,
                      onTap: () => _openItem(it),
                      onLongPress: () => _handleLongPressItem(it),
                    );
                  },
                );
              },
            );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(key: ValueKey(_viewMode), child: view),
    );
  }

  Future<void> _openVideoChooser(
    BuildContext context,
    String identifier,
    String title,
    List<Map<String, dynamic>> videoFiles,
  ) async {
    if (_isDisposed) return;

    final options =
        videoFiles.map<Map<String, String>>((f) {
          final name = (f['name'] ?? '').toString();
          final fmt = (f['format'] ?? '').toString();
          final w = int.tryParse('${f['width'] ?? ''}');
          final h = int.tryParse('${f['height'] ?? ''}');
          final size = int.tryParse('${f['size'] ?? ''}');

          final nameRes = RegExp(r'(\d{3,4})p').firstMatch(name)?.group(1);
          final resLabel =
              (w != null && h != null)
                  ? '${w}x$h'
                  : (nameRes != null ? '${nameRes}p' : 'Unknown');

          final sizeLabel = _humanBytes(size);
          final pretty = _prettyFilename(name);
          final url =
              'https://archive.org/download/$identifier/${Uri.encodeComponent(name)}';

          return {
            'url': url,
            'fmt': fmt.toLowerCase(),
            'name': name,
            'pretty': pretty,
            'res': resLabel,
            'size': sizeLabel,
          };
        }).toList();

    if (!mounted) return;

    _dismissKeyboard();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.85;
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
                  subtitle: const Text('Choose a file and how to open it'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final op = options[i];
                      final icon =
                          op['fmt']!.contains('mp4') ||
                                  op['fmt']!.contains('h.264')
                              ? Icons.movie
                              : Icons.video_file;

                      return ListTile(
                        leading: Icon(icon),
                        title: Text(
                          op['pretty']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${(op['fmt'] ?? '').toUpperCase()}  •  ${op['res']}  •  ${op['size']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          if (!mounted || _isDisposed) return;

                          final uri = Uri.parse(op['url']!);

                          final fmtUp = (op['fmt'] ?? '').toUpperCase();
                          final size = op['size'] ?? '';
                          final pretty = op['pretty'] ?? '';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                              content: Text(' $pretty • $fmtUp • $size'),
                            ),
                          );

                          final choice = await showDialog<String>(
                            context: context,
                            builder:
                                (dCtx) => AlertDialog(
                                  title: const Text('Open video'),
                                  content: const SingleChildScrollView(
                                    child: Text(
                                      'Choose how you’d like to open this video:',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(dCtx, 'browser'),
                                      child: const Text('Browser'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(dCtx, 'app'),
                                      child: const Text('Installed app'),
                                    ),
                                    ElevatedButton(
                                      onPressed:
                                          () => Navigator.pop(dCtx, 'inapp'),
                                      child: const Text('In-app player'),
                                    ),
                                  ],
                                ),
                          );
                          if (choice == null) return;

                          if (mounted) Navigator.pop(context); // close sheet

                          final name = op['name'] as String;
                          final videoUrl =
                              'https://archive.org/download/$identifier/$name';

                          await RecentProgressService.instance.updateVideo(
                            id: identifier,
                            title: title,
                            thumb: archiveThumbUrl(identifier),
                            percent: 0.0,
                            fileUrl: videoUrl,
                            fileName: name,
                          );

                          String mime = 'video/*';
                          final fmt =
                              (op['fmt'] ?? '').toString().toLowerCase();
                          final nameLower = name.toLowerCase();
                          if (fmt.contains('webm') ||
                              nameLower.endsWith('.webm')) {
                            mime = 'video/webm';
                          } else if (fmt.contains('mp4') ||
                              fmt.contains('h.264') ||
                              nameLower.endsWith('.mp4') ||
                              nameLower.endsWith('.m4v')) {
                            mime = 'video/mp4';
                          } else if (fmt.contains('matroska') ||
                              nameLower.endsWith('.mkv')) {
                            mime = 'video/x-matroska';
                          } else if (nameLower.endsWith('.m3u8')) {
                            mime = 'application/vnd.apple.mpegurl';
                          }

                          if (!mounted || _isDisposed) return;
                          _dismissKeyboard();

                          if (choice == 'inapp') {
                            Navigator.of(context).push(
                              _sharedAxisRoute(
                                VideoPlayerScreen(
                                  url: videoUrl,
                                  file: null,
                                  identifier: identifier,
                                  title: title,
                                ),
                              ),
                            );
                          } else if (choice == 'browser') {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            await openExternallyWithChooser(
                              url: uri.toString(),
                              mimeType: mime,
                              chooserTitle: 'Open with',
                            );
                          }
                        },
                      );
                    },
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

// ---------- UI helpers (unchanged, except imports) ----------
class _CenteredSpinner extends StatelessWidget {
  final String label;
  const _CenteredSpinner({required this.label});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenWeb;
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    this.onOpenWeb,
  });
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 32),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                if (onOpenWeb != null)
                  OutlinedButton.icon(
                    onPressed: onOpenWeb,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View on web'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenWeb;
  const _EmptyPane({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
    this.onOpenWeb,
  });
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 36),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                if (onOpenWeb != null)
                  OutlinedButton.icon(
                    onPressed: onOpenWeb,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View on web'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  final String id;
  final String title;
  final String mediatype;
  final String? year;
  final String? thumb;
  final bool highlight;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GridCard({
    required this.id,
    required this.title,
    required this.mediatype,
    this.year,
    required this.thumb,
    required this.highlight,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final thumbUrl =
        (thumb != null && thumb!.trim().isNotEmpty)
            ? thumb!
            : archiveThumbUrl(id);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(kCapsuleRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CapsuleThumbCard(
                heroTag: 'thumb:$id',
                imageUrl: thumbUrl,
                fit: BoxFit.cover,
                fillParent: true,
                topRightOverlay:
                    mediatype.isNotEmpty
                        ? mediaTypePill(context, mediatype)
                        : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListTileCard extends StatelessWidget {
  final String id;
  final String title;
  final String subtitle;
  final String mediatype;
  final String? year;
  final String? thumb;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ListTileCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.mediatype,
    this.year,
    required this.thumb,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final thumbUrl =
        (thumb != null && thumb!.trim().isNotEmpty)
            ? thumb!
            : archiveThumbUrl(id);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(kCapsuleRadius),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: CapsuleThumbCard(
              heroTag: 'thumb:$id',
              imageUrl: thumbUrl,
              aspectRatio: 3 / 4,
              fit: BoxFit.cover,
              topRightOverlay:
                  mediatype.isNotEmpty
                      ? mediaTypePill(context, mediatype)
                      : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall!.copyWith(
                        color: textTheme.bodySmall?.color?.withOpacity(0.75),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final String label;
  final SortMode value;
  final SortMode current;
  final ValueChanged<SortMode> onSelect;
  const _SortTile(
    this.label,
    this.value,
    this.current,
    this.onSelect, {
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return ListTile(
      title: Text(label),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => onSelect(value),
    );
  }
}

class _CollectionQuickPick extends StatelessWidget {
  final String title;
  final List<Map<String, String>> items;
  final VoidCallback onSeeAll;

  const _CollectionQuickPick({
    required this.title,
    required this.items,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.8;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${items.length}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final it = items[i];
                  final id = it['identifier']!;
                  final mediatype = (it['mediatype'] ?? '').toUpperCase();
                  final thumbUrl =
                      (it['thumb']?.isNotEmpty == true)
                          ? it['thumb']!
                          : archiveFallbackThumbUrl(id);

                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: thumbUrl,
                        width: 48,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget:
                            (_, __, ___) => Image.network(
                              archiveFallbackThumbUrl(id),
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                      ),
                    ),
                    title: Text(
                      it['title'] ?? id,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      mediatype,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      final id = it['identifier'] as String;
                      final title =
                          (it['title'])?.trim().isNotEmpty == true
                              ? it['title'] as String
                              : id;
                      final mt = (it['mediatype'] ?? '').toLowerCase();
                      final kind =
                          mt.contains('pdf')
                              ? 'pdf'
                              : mt.contains('epub')
                              ? 'epub'
                              : mt.contains('video')
                              ? 'video'
                              : mt.contains('audio')
                              ? 'audio'
                              : 'collection';
                      final thumb =
                          (it['thumb'] as String?)?.trim().isNotEmpty == true
                              ? it['thumb'] as String
                              : archiveFallbackThumbUrl(id);

                      await RecentProgressService.instance.touch(
                        id: id,
                        title: title,
                        thumb: thumb,
                        kind: kind,
                      );

                      Navigator.of(context).pop(it);
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSeeAll,
                      icon: const Icon(Icons.open_in_full),
                      label: const Text('See all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
