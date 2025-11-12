// path: lib/screens/collection_detail_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:animations/animations.dart';
import 'package:archivereader/services/app_preferences.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/services/sfw_filter.dart' as sfw;
import 'package:archivereader/services/thumb_override_service.dart';
import 'package:archivereader/services/thumbnail_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:archivereader/widgets/favourite_add_dialogue.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../archive_api.dart'; // fetch files when adding to favourites
import '../net.dart';
import '../utils/archive_helpers.dart';
import '../widgets/video_chooser.dart'; // shared video chooser
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
const int _CHILD_ROWS = 36;

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

class CollectionDetailScreen extends StatefulWidget {
  final String categoryName;
  final String? collectionName;
  final String? customQuery;

  const CollectionDetailScreen({
    super.key,
    required this.categoryName,
    this.collectionName,
    this.customQuery,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final ValueNotifier<bool> _sfwOnlyNotifier;

  static final http.Client _client = http.Client();
  static const Duration _netTimeout = Duration(seconds: 12);

  final List<Map<String, String>> _items = <Map<String, String>>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _requestToken = 0;
  static const int _rows = 60;
  int _page = 1;
  int _numFound = 0;

  bool get _hasMore => _items.length < _numFound;

  SortMode _sort = SortMode.popularAllTime;
  SearchScope _searchScope = SearchScope.metadata;
  ViewMode _viewMode = ViewMode.grid;

  bool _showScrollTop = false;
  bool _isDisposed = false;

  // WHY: Used to cache files with correct formats when saving favourites.
  String _inferFormatFrom(String name, String? fmt) {
    final f = (fmt ?? '').trim();
    if (f.isNotEmpty) return f;
    final m = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(name);
    return (m?.group(1) ?? '').toLowerCase();
  }

  String? _toStr(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  List<Map<String, String>> _mapFilesForCache(List<Map<String, String>> files) {
    return files
        .where((f) => (f['name'] ?? '').toString().trim().isNotEmpty)
        .map((f) {
          final name = (f['name'] ?? '').toString();
          final fmt = _inferFormatFrom(name, f['format']);
          return <String, String>{
            'name': name,
            'format': fmt,
            if (_toStr(f['size']) != null) 'size': _toStr(f['size'])!,
            if (_toStr(f['width']) != null) 'width': _toStr(f['width'])!,
            if (_toStr(f['height']) != null) 'height': _toStr(f['height'])!,
          };
        })
        .toList(growable: false);
  }

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
    _sfwOnlyNotifier = ValueNotifier<bool>(true);
    _loadSfwSetting();
    _init();

    _sfwOnlyNotifier.addListener(() {
      if (mounted) _fetch(reset: true);
    });

    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 400;
      if (show != _showScrollTop && mounted) {
        setState(() => _showScrollTop = show);
      }
    });
  }

  Future<void> _loadSfwSetting() async {
    final sfw = await AppPreferences.instance.sfwOnly;
    if (mounted) _sfwOnlyNotifier.value = sfw;
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
    _sfwOnlyNotifier.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && !focus.hasPrimaryFocus) {
      focus.unfocus();
    }
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
    if (_sfwOnlyNotifier.value) {
      full = '($full)${sfw.SfwFilter.serverExclusionSuffix()}';
    }
    return full;
  }

  Future<Map<String, dynamic>> _decodeJson(String body) async {
    return compute((String s) => jsonDecode(s) as Map<String, dynamic>, body);
  }

  Future<void> _unblockSmartThumbs(
    List<Map<String, String>> batch, {
    required int currentToken,
  }) async {
    const int kMaxConcurrent = 6;
    final Map<int, String> thumbUpdates = {};

    Future<void> process(Map<String, String> item) async {
      try {
        if (!mounted || _isDisposed || currentToken != _requestToken) return;

        final id = item['identifier']!;
        final mediatype = item['mediatype'] ?? '';
        final title = item['title'] ?? id;
        final year = item['year'] ?? '';

        final currentThumb = (item['thumb'] ?? '').trim();
        final placeholder = archiveThumbUrl(id);
        if (currentThumb.isNotEmpty && currentThumb != placeholder) return;

        final smart = await ThumbnailService().getSmartThumb(
          id: id,
          mediatype: mediatype,
          title: title,
          year: year,
        );

        if (!mounted || _isDisposed || currentToken != _requestToken) return;
        if (smart.isEmpty || smart == currentThumb) return;

        final idx = _items.indexWhere((e) => e['identifier'] == id);
        if (idx != -1) thumbUpdates[idx] = smart;
      } catch (_) {}
    }

    for (int i = 0; i < batch.length; i += kMaxConcurrent) {
      if (!mounted || _isDisposed || currentToken != _requestToken) return;
      final end = (i + kMaxConcurrent).clamp(0, batch.length);
      final slice = batch.sublist(i, end);
      await Future.wait(slice.map(process));
    }

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
    final int token = ++_requestToken;

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
      if (mounted && token == _requestToken) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = 'No collection or custom query provided.';
        });
      }
      return;
    }

    try {
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

      final resp = await _client
          .get(Uri.parse(url), headers: _HEADERS)
          .timeout(_netTimeout);

      if (!mounted || _isDisposed || token != _requestToken) return;

      if (resp.statusCode != 200) {
        throw Exception('Search failed (${resp.statusCode}).');
      }

      final data = await _decodeJson(resp.body);
      final response = (data['response'] as Map<String, dynamic>?) ?? const {};
      final List docs = (response['docs'] as List?) ?? const [];
      _numFound = (response['numFound'] as int?) ?? _numFound;

      String flat(dynamic v) {
        if (v == null) return '';
        if (v is List) {
          return v.whereType<Object>().map((e) => e.toString()).join(', ');
        }
        return v.toString();
      }

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

      if (_sfwOnlyNotifier.value) {
        final filtered = batch.where(sfw.SfwFilter.isClean).toList();
        if (filtered.isNotEmpty || _searchCtrl.text.trim().isNotEmpty) {
          batch = filtered;
        }
      }

      await ThumbOverrideService.instance.applyToItemMaps(batch);

      final existingIds = _items.map((m) => m['identifier']).toSet();
      batch =
          batch.where((m) {
            final id = m['identifier'] ?? '';
            return id.isNotEmpty && !existingIds.contains(id);
          }).toList();

      if (mounted && !_isDisposed && token == _requestToken) {
        setState(() {
          _items.addAll(batch);
          _error = null;
        });
      }

      unawaited(_unblockSmartThumbs(batch, currentToken: token));
    } catch (e) {
      if (mounted && token == _requestToken) {
        setState(() {
          _error = 'Network error. Please try again.';
        });
      }
    } finally {
      if (mounted && token == _requestToken) {
        setState(() {
          if (reset) _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    await _fetch(reset: true);
  }

  void _runSearch() => _fetch(reset: true);

  Future<void> _handleLongPressItem(Map<String, String> item) async {
    if (_isDisposed) return;

    HapticFeedback.mediumImpact();
    _dismissKeyboard();

    final messenger = ScaffoldMessenger.maybeOf(context);
    final id = item['identifier']!;
    final title = (item['title'] ?? id).trim().isNotEmpty ? item['title']! : id;
    final mediatype = item['mediatype'] ?? '';
    final year = item['year'] ?? '';
    final safeThumb =
        (item['thumb']?.trim().isNotEmpty == true)
            ? item['thumb']!.trim()
            : archiveThumbUrl(id); // why: FavoriteItem.thumb can be null

    final svc = FavoritesService.instance;
    try {
      await svc.init();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Favourites init failed: $e')),
      );
      return;
    }

    final fav = FavoriteItem(
      id: id,
      title: title,
      url: 'https://archive.org/details/$id',
      thumb: safeThumb,
    );

    if (svc.folders().isEmpty) {
      try {
        await svc.createFolder('Favourites');
      } catch (e) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Couldn’t create folder: $e')),
        );
      }
    }

    final titleCtrl = TextEditingController(text: title);
    bool isSearching = false;
    bool enrichEnabled = false;

    void safePop<T extends Object?>(T? result) {
      if (!mounted || _isDisposed) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop<T>(result);
      });
    }

    final result = await showDialog<DialogResult>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            bool dialogClosing = false;

            Future<void> enrich() async {
              if (dialogClosing) return;
              setDialogState(() => enrichEnabled = true);
              try {
                final updated = Map<String, String>.from(item);
                await ThumbnailService().enrichItemWithTmdb(updated);
                final idx = _items.indexWhere((i) => i['identifier'] == id);
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
              } finally {
                if (!dialogClosing && dialogCtx.mounted) {
                  setDialogState(() => enrichEnabled = false);
                }
              }
            }

            Future<void> searchAndPickPoster() async {
              if (dialogClosing) return;
              final query = titleCtrl.text.trim();
              if (query.isEmpty) {
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a title'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              setDialogState(() => isSearching = true);
              try {
                final chosen = await ThumbnailService().choosePosterRich(
                  context,
                  query,
                  year: year.isNotEmpty ? year : null,
                  currentTitle: title,
                );
                if (chosen == null) return;

                await FavoritesService.instance.updateThumbForId(id, chosen);

                final idx = _items.indexWhere((i) => i['identifier'] == id);
                if (idx != -1 && mounted && !_isDisposed) {
                  setState(() => _items[idx]['thumb'] = chosen);
                }
                await ThumbOverrideService.instance.set(id, chosen);

                messenger?.showSnackBar(
                  SnackBar(
                    content: const Text('Thumbnail updated!'),
                    backgroundColor: Colors.green,
                    action: SnackBarAction(
                      label: 'View',
                      onPressed: () => launchUrl(Uri.parse(chosen)),
                    ),
                  ),
                );

                dialogClosing = true;
                safePop<DialogResult>(DialogResult.generateThumb);
              } catch (e) {
                messenger?.showSnackBar(
                  SnackBar(
                    content: Text('Search failed: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                if (!dialogClosing && dialogCtx.mounted) {
                  setDialogState(() => isSearching = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Options'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.favorite_border),
                      title: const Text('Add to Favourites'),
                      subtitle: Text('Add "$title" to a folder'),
                      onTap: () {
                        dialogClosing = true;
                        safePop<DialogResult>(DialogResult.addToFolder);
                      },
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      value: enrichEnabled,
                      onChanged: (_) => enrich(),
                      title: const Text('Enrich Metadata'),
                      subtitle: const Text(
                        'Pull title, year, description, and poster from TMDb',
                      ),
                    ),
                    const Divider(height: 16),
                    if (mediatype.toLowerCase().contains('video') ||
                        mediatype == 'movies') ...[
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
                                    onPressed: searchAndPickPoster,
                                  ),
                        ),
                      ),
                      if (year.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Year: $year',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => safePop<void>(null),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    if (!mounted || _isDisposed) return;

    if (result == DialogResult.addToFolder) {
      try {
        // Fetch files if not already available; cache with inferred format.
        List<Map<String, String>> cachedFiles = fav.files ?? const [];
        if (cachedFiles.isEmpty) {
          try {
            final fetched = await ArchiveApi.fetchFilesForIdentifier(id);
            cachedFiles = _mapFilesForCache(
              fetched.map((e) => Map<String, String>.from(e)).toList(),
            );
          } catch (_) {
            cachedFiles = const [];
          }
        }

        final favWithFiles = fav.copyWith(files: cachedFiles);

        final folder = await showAddToFavoritesDialog(
          context,
          item: favWithFiles,
        );
        if (folder != null) {
          await svc.addToFolder(folder, favWithFiles);
          messenger?.showSnackBar(
            SnackBar(content: Text('Added to "$folder"')),
          );
        }
      } catch (e) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Failed to add to favourites: $e')),
        );
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

      if (mediatype == 'texts') {
        final rawFiles = (m['files'] as List?) ?? const <dynamic>[];

        final pdfFiles = <Map<String, dynamic>>[];
        final imgFiles = <Map<String, dynamic>>[];
        final txtFiles = <Map<String, dynamic>>[];
        final epubFiles = <Map<String, dynamic>>[];

        for (final f in rawFiles) {
          if (f is! Map) continue;
          final map = f.cast<String, dynamic>();
          final name = (map['name'] ?? '').toString().toLowerCase();
          final fmt = (map['format'] ?? '').toString().toLowerCase();

          if (name.endsWith('.pdf') || fmt.contains('pdf')) {
            pdfFiles.add(map);
          } else if (name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.gif') ||
              name.endsWith('.webp') ||
              fmt.contains('jpeg') ||
              fmt.contains('png') ||
              fmt.contains('gif') ||
              fmt.contains('webp')) {
            imgFiles.add(map);
          } else if (name.endsWith('.txt') ||
              name.endsWith('.md') ||
              name.endsWith('.log') ||
              name.endsWith('.csv') ||
              fmt.contains('text') ||
              fmt.contains('plain')) {
            txtFiles.add(map);
          } else if (name.endsWith('.epub')) {
            epubFiles.add(map);
          }
        }

        final options = <String, VoidCallback>{};

        if (pdfFiles.isNotEmpty) {
          options['PDF Document${pdfFiles.length > 1 ? ' (${pdfFiles.length})' : ''}'] =
              () async {
                if (pdfFiles.length == 1) {
                  final file = pdfFiles.first;
                  final name = file['name'] as String;
                  final url =
                      'https://archive.org/download/$id/${Uri.encodeComponent(name)}';
                  await RecentProgressService.instance.touch(
                    id: id,
                    title: item['title'] ?? id,
                    thumb: archiveThumbUrl(id),
                    kind: 'pdf',
                    fileUrl: url,
                    fileName: name,
                  );
                  if (!mounted || _isDisposed) return;
                  Navigator.of(context).push(
                    _sharedAxisRoute(
                      PdfViewerScreen(
                        url: url,
                        filenameHint: name,
                        identifier: id,
                        title: item['title'] ?? id,
                      ),
                    ),
                  );
                } else {
                  final list =
                      pdfFiles
                          .map((f) => {'name': f['name'] as String})
                          .cast<Map<String, String>>()
                          .toList();
                  Navigator.of(context).push(
                    _sharedAxisRoute(
                      ArchiveItemScreen(
                        title: item['title'] ?? id,
                        identifier: id,
                        files: list,
                      ),
                    ),
                  );
                }
              };
        }

        if (imgFiles.isNotEmpty) {
          options['Image Gallery${imgFiles.length > 1 ? ' (${imgFiles.length})' : ''}'] =
              () async {
                final urls =
                    imgFiles
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
                ).push(_sharedAxisRoute(ImageViewerScreen(imageUrls: urls)));
              };
        }

        if (txtFiles.isNotEmpty) {
          options['Text File${txtFiles.length > 1 ? ' (${txtFiles.length})' : ''}'] =
              () async {
                final file = txtFiles.first;
                final name = file['name'] as String;
                final url =
                    'https://archive.org/download/$id/${Uri.encodeComponent(name)}';
                await RecentProgressService.instance.touch(
                  id: id,
                  title: item['title'] ?? id,
                  thumb: archiveThumbUrl(id),
                  kind: 'text',
                  fileUrl: url,
                  fileName: name,
                );
                if (!mounted || _isDisposed) return;
                Navigator.of(context).push(
                  _sharedAxisRoute(
                    TextViewerScreen(
                      url: url,
                      filenameHint: name,
                      identifier: id,
                      title: item['title'] ?? id,
                    ),
                  ),
                );
              };
        }

        if (options.isEmpty) {
          final list =
              rawFiles
                  .whereType<Map>()
                  .map((f) => f.cast<String, dynamic>())
                  .where((f) => (f['name'] as String?)?.isNotEmpty == true)
                  .map<Map<String, String>>(
                    (f) => {'name': f['name'] as String},
                  )
                  .toList();

          if (list.isEmpty) {
            final ok = await launchUrl(
              Uri.parse('https://archive.org/details/$id'),
              mode: LaunchMode.externalApplication,
            );
            if (!ok && mounted && !_isDisposed) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('No files found')));
            }
            return;
          }

          Navigator.of(context).push(
            _sharedAxisRoute(
              ArchiveItemScreen(
                title: item['title'] ?? id,
                identifier: id,
                files: list,
              ),
            ),
          );
          return;
        }

        if (!mounted || _isDisposed) return;
        _dismissKeyboard();

        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder:
              (ctx) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Open as...',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...options.entries.map(
                        (e) => ListTile(
                          leading: Icon(
                            e.key.contains('PDF')
                                ? Icons.picture_as_pdf
                                : e.key.contains('Image')
                                ? Icons.photo_library
                                : e.key.contains('Text')
                                ? Icons.description
                                : e.key.contains('Comic')
                                ? Icons.book
                                : Icons.menu_book,
                          ),
                          title: Text(e.key),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            e.value();
                          },
                        ),
                      ),
                      const Divider(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        );
        return;
      }

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
            fmt.contains('webm') ||
            lower.endsWith('.mp4') ||
            lower.endsWith('.m4v') ||
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
        await showVideoChooser(
          context,
          identifier: id,
          title: item['title'] ?? id,
          files: videoFiles,
        );
        return;
      }

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
                    ),
                  ),
                );
              },
            ),
      );
      if (selected != null) await _openItem(selected);
      return;
    }

    Navigator.of(context).push(
      _sharedAxisRoute(
        CollectionDetailScreen(
          categoryName: title,
          collectionName: collectionId,
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

      if (_sfwOnlyNotifier.value) {
        items = items.where(sfw.SfwFilter.isClean).toList();
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

  Widget _buildBody(ColorScheme cs) {
    if (_loading) return const _CenteredSpinner(label: 'Loading…');
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
}

// UI HELPERS
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
  const _SortTile(this.label, this.value, this.current, this.onSelect);
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
                          (it['thumb'])?.trim().isNotEmpty == true
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
