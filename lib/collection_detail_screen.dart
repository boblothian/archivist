// collection_detail_screen.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:archivereader/widgets/favourite_add_dialogue.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'archive_item_screen.dart';
import 'net.dart';

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

String _kindFor(dynamic item) {
  final mt = (item.mediaType ?? item.format ?? '').toString().toLowerCase();
  if (mt.contains('pdf')) return 'pdf';
  if (mt.contains('epub')) return 'epub';
  if (mt.contains('video')) return 'video';
  if (mt.contains('audio')) return 'audio';
  return 'collection';
}

enum SearchScope { metadata, title }

enum ViewMode { grid, list }

const int _QUICK_PICK_LIMIT = 24;
const int _CHILD_ROWS = 60;

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

String _thumbForId(String id) => 'https://archive.org/services/img/$id';
String _fallbackThumbForId(String id) =>
    'https://archive.org/download/$id/$id.jpg';

class _SfwFilter {
  static final List<RegExp> _bad = <RegExp>[
    RegExp(r'\bnsfw\b', caseSensitive: false),
    RegExp(r'\bexplicit\b', caseSensitive: false),
    RegExp(r'\bporn\b', caseSensitive: false),
    RegExp(r'\badult\b', caseSensitive: false),
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

  final List<Map<String, String>> _items = <Map<String, String>>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _requestToken = 0;
  static const int _rows = 120;
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
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _prettyFilename(String raw) {
    var s = raw;
    s = s.replaceFirst(RegExp(r'\.(mp4|mkv|webm)$', caseSensitive: false), '');
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

  Future<void> _fetch({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _numFound = 0;
      _items.clear();
      _error = null;
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }

    if ((widget.collectionName == null ||
            widget.collectionName!.trim().isEmpty) &&
        (widget.customQuery == null || widget.customQuery!.trim().isEmpty)) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'No collection or custom query provided.';
      });
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
    ].map((f) => 'fl[]=$f').join('&');

    final url =
        'https://archive.org/advancedsearch.php?'
        'q=${Uri.encodeQueryComponent(q)}&'
        '$flParams&sort[]=${Uri.encodeQueryComponent(_sortParam(_sort))}&'
        'rows=$_rows&page=$_page&output=json';

    try {
      final resp = await http.get(Uri.parse(url), headers: _HEADERS);
      if (!mounted || token != _requestToken) return;

      if (resp.statusCode != 200) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = 'Search failed (${resp.statusCode}).';
        });
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
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

      List<Map<String, String>> batch =
          docs.map<Map<String, String>>((doc) {
            final id = (doc['identifier'] ?? '').toString();
            final title = flat(doc['title']).trim();
            return {
              'identifier': id,
              'title': title.isEmpty ? id : title,
              'thumb': _thumbForId(id),
              'mediatype': flat(doc['mediatype']),
              'description': flat(doc['description']),
              'creator': flat(doc['creator']),
              'subject': flat(doc['subject']),
            };
          }).toList();

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

      setState(() {
        _items.addAll(batch);
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Network error. Please try again.';
      });
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    await _fetch(reset: true);
  }

  void _runSearch() => _fetch(reset: true);

  Future<void> _openItem(Map<String, String> item) async {
    final id = item['identifier']!;
    HapticFeedback.selectionClick();

    try {
      final resp = await http.get(
        Uri.parse('https://archive.org/metadata/$id'),
        headers: _HEADERS,
      );
      if (!mounted) return;

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

      final rawFiles = (m['files'] as List?) ?? const <dynamic>[];
      final files = <Map<String, dynamic>>[];
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
        files.add({
          'name': name,
          'format': fmt,
          'isVideo': isVideo,
          'width': f['width'],
          'height': f['height'],
          'size': f['size'],
        });
      }

      final videoFiles = files.where((f) => (f['isVideo'] as bool)).toList();

      if (videoFiles.isNotEmpty) {
        await _openVideoChooser(context, id, item['title'] ?? id, videoFiles);
        return;
      }

      final justNames =
          files
              .where((f) => (f['name'] as String).isNotEmpty)
              .map<Map<String, String>>((f) => {'name': f['name'] as String})
              .toList();

      if (justNames.isEmpty) {
        final ok = await launchUrl(
          Uri.parse('https://archive.org/details/$id'),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No files found and cannot open on web.'),
            ),
          );
        }
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ArchiveItemScreen(
                title: item['title'] ?? id,
                identifier: id,
                files: justNames,
              ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open item (network).')),
      );
    }
  }

  Future<void> _openCollectionSmart(String collectionId, String title) async {
    final children = await _fetchCollectionChildren(collectionId);
    if (!mounted) return;

    if (children.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
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
                  MaterialPageRoute(
                    builder:
                        (_) => CollectionDetailScreen(
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
      MaterialPageRoute(
        builder:
            (_) => CollectionDetailScreen(
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

  Future<void> openExternallyWithChooser({
    required String url,
    required String mimeType, // e.g. 'video/*', 'audio/*', 'application/pdf'
    String chooserTitle = 'Open with',
  }) async {
    if (!Platform.isAndroid) {
      // fallback to url_launcher on iOS/desktop
      if (!Platform.isAndroid) {
        // fallback to url_launcher on iOS/desktop
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Base VIEW intent
    final viewIntent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: url, // http(s)://, content://, file://
      type: mimeType, // <-- IMPORTANT for resolver to show correct apps
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        // Grant read permission if you're passing a content:// URI
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
      ],
    );

    // Most versions of android_intent_plus support this convenience:
    try {
      await viewIntent.launchChooser(chooserTitle);
      return;
    } catch (_) {
      // If your plugin version lacks launchChooser, build ACTION_CHOOSER manually:
      final chooserIntent = AndroidIntent(
        action: 'android.intent.action.CHOOSER',
        // EXTRA_INTENT expects a parcelable intent; plugin accepts map via extras
        arguments: <String, dynamic>{
          'android.intent.extra.INTENT': viewIntent,
          'android.intent.extra.TITLE': chooserTitle,
        },
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await chooserIntent.launch();
    }
  }

  Future<List<Map<String, String>>> _fetchCollectionChildren(
    String collectionId,
  ) async {
    final q = 'collection:$collectionId';
    final flParams = <String>[
      'identifier',
      'title',
      'mediatype',
      'subject',
      'creator',
      'description',
    ].map((f) => 'fl[]=$f').join('&');

    final url =
        'https://archive.org/advancedsearch.php?'
        'q=${Uri.encodeQueryComponent(q)}&'
        '$flParams&sort[]=${Uri.encodeQueryComponent('downloads desc')}&'
        'rows=$_CHILD_ROWS&page=1&output=json';

    try {
      final resp = await http.get(Uri.parse(url), headers: _HEADERS);
      if (resp.statusCode != 200) return const <Map<String, String>>[];

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
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
            return {
              'identifier': id,
              'title': title.isEmpty ? id : title,
              'thumb': _thumbForId(id),
              'mediatype': flat(doc['mediatype']),
              'description': flat(doc['description']),
              'creator': flat(doc['creator']),
              'subject': flat(doc['subject']),
            };
          }).toList();

      if (_sfwOnly) items = items.where(_SfwFilter.isClean).toList();
      if (_favouritesOnly) {
        final favs =
            FavoritesService.instance.allItems.map((e) => e.id).toSet();
        items = items.where((m) => favs.contains(m['identifier'])).toList();
      }

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

  int _computeCrossAxis(double w) {
    if (w >= 1280) return 6;
    if (w >= 1024) return 5;
    if (w >= 840) return 4;
    if (w >= 600) return 3;
    return 2;
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
                    controller: _searchCtrl,
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

  Future<bool> _openWithInstalledApp(Uri uri) async {
    try {
      if (Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: uri.toString(),
          type: 'video/*',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return true;
      } else {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      }
    } catch (_) {
      return false;
    }
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
          FilterChip(
            label: const Text('Favourites'),
            selected: _favouritesOnly,
            onSelected: (v) {
              setState(() => _favouritesOnly = v);
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

    if (_viewMode == ViewMode.list) {
      return ListView.builder(
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
            thumb: it['thumb']!,
            mediatype: it['mediatype'] ?? '',
            onTap: () => _openItem(it),
            onLongPress: () => _handleLongPressItem(it),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cross = _computeCrossAxis(c.maxWidth);
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
              thumb: it['thumb']!,
              mediatype: it['mediatype'] ?? '',
              highlight: isCollection,
              onTap: () => _openItem(it),
              onLongPress: () => _handleLongPressItem(it),
            );
          },
        );
      },
    );
  }

  // Unified long-press handler
  // lib/screens/collection_detail_screen.dart
  // ... (your full code, but update the _handleLongPressItem to this)

  Future<void> _handleLongPressItem(Map<String, String> item) async {
    HapticFeedback.mediumImpact();

    final id = item['identifier']!;
    final fav = FavoriteItem(
      id: id,
      title: item['title'] ?? id,
      url: 'https://archive.org/details/$id',
      thumb: item['thumb']!,
    );

    final svc = FavoritesService.instance;
    if (svc.folders().isEmpty) {
      await svc.createFolder('Favourites');
    }

    final folder = await showAddToFavoritesDialog(context, item: fav);

    if (folder != null && context.mounted) {
      await svc.addToFolder(folder, fav);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added to "$folder"')));

      // Auto-open the folder
      /*Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FavoritesScreen(initialFolder: folder),
        ),
      );*/
    }
  }

  Future<void> _openVideoChooser(
    BuildContext context,
    String identifier,
    String title,
    List<Map<String, dynamic>> videoFiles,
  ) async {
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

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
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
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
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
                        final uri = Uri.parse(op['url']!);

                        if (context.mounted) {
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
                        }

                        // Ask how to open
                        final choice = await showDialog<String>(
                          context: context,
                          builder:
                              (dCtx) => AlertDialog(
                                title: const Text('Open video'),
                                content: const Text(
                                  'Choose how you’d like to open or save this video:',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(dCtx, 'browser'),
                                    child: const Text('Browser'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(dCtx, 'app'),
                                    child: const Text('Installed app'),
                                  ),
                                ],
                              ),
                        );
                        if (choice == null) return;

                        // Close the sheet before launching
                        if (mounted) Navigator.pop(context);

                        // Best-effort MIME from format/extension
                        String mime = 'video/*';
                        final fmt = (op['fmt'] ?? '').toString().toLowerCase();
                        final nameLower =
                            (op['name'] ?? '').toString().toLowerCase();
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

                        // Log as “viewed / watched”
                        await RecentProgressService.instance.touch(
                          id: identifier,
                          title: title,
                          thumb: _thumbForId(identifier),
                          kind: 'video',
                        );

                        if (choice == 'browser') {
                          // Open in default external handler (likely browser)
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          // Force Android chooser so the popup appears
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
        );
      },
    );
  }
}

// ---------- UI helpers ----------

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
  final String thumb;
  final String mediatype;
  final bool highlight;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GridCard({
    required this.id,
    required this.title,
    required this.thumb,
    required this.mediatype,
    required this.highlight,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      // ensures InkWell ripple without layout impact
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(kCapsuleRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // WHY: allow the image to flex so Column never overflows
              child: CapsuleThumbCard(
                heroTag: 'thumb:$id',
                imageUrl: thumb,
                fit: BoxFit.contain,
                fillParent: true, // NEW: react to available height
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
  final String thumb;
  final String mediatype;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ListTileCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumb,
    required this.mediatype,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
              imageUrl: thumb,
              aspectRatio: 3 / 4,
              fit: BoxFit.contain,
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
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        httpHeaders: Net.headers,
                        imageUrl: it['thumb']!,
                        width: 48,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget:
                            (_, __, ___) => Image.network(
                              _fallbackThumbForId(id),
                              headers: Net.headers,
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) =>
                                      const Icon(Icons.broken_image),
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
                          (it['title'] as String?)?.trim().isNotEmpty == true
                              ? it['title'] as String
                              : id;
                      final mt =
                          (it['mediatype'] as String? ?? '').toLowerCase();
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
                              : _fallbackThumbForId(id);

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
            Divider(height: 1),
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
