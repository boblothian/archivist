// lib/screens/collection_search_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:archivereader/collection_store.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../archive_api.dart'; // ← brings in ArchiveCollection + ArchiveCollectionJson extension
import 'collection_detail_screen.dart';

/// Simple in-memory + SharedPreferences cache for search results.
/// Uses the ArchiveCollectionJson extension defined in archive_api.dart
class _SearchCache {
  static const _ttlMinutes = 30;
  static final _memory = <String, List<ArchiveCollection>>{};

  static Future<List<ArchiveCollection>?> get(String query) async {
    query = query.trim();
    if (_memory.containsKey(query)) {
      return _memory[query];
    }

    final prefs = await SharedPreferences.getInstance();
    final key = 'search_cache:$query';
    final raw = prefs.getString(key);
    if (raw == null) return null;

    final map = jsonDecode(raw) as Map<String, dynamic>;
    final ts = map['_ts'] as int?;
    if (ts == null ||
        DateTime.now().millisecondsSinceEpoch - ts > _ttlMinutes * 60 * 1000) {
      await prefs.remove(key);
      return null;
    }

    final list =
        (map['data'] as List)
            .map(
              (e) => ArchiveCollectionJson.fromJson(e as Map<String, dynamic>),
            )
            .toList();
    _memory[query] = list;
    return list;
  }

  static Future<void> set(String query, List<ArchiveCollection> results) async {
    query = query.trim();
    _memory[query] = results;

    final prefs = await SharedPreferences.getInstance();
    final key = 'search_cache:$query';
    final payload = {
      '_ts': DateTime.now().millisecondsSinceEpoch,
      'data':
          results.map((c) => c.toJson()).toList(), // toJson() from extension
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  static Future<void> clear() async {
    _memory.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('search_cache:'));
    for (final k in keys) await prefs.remove(k);
  }
}

class CollectionSearchScreen extends StatefulWidget {
  final ValueNotifier<bool>? activateTrigger;

  const CollectionSearchScreen({Key? key, this.activateTrigger})
    : super(key: key);

  @override
  State<CollectionSearchScreen> createState() => _CollectionSearchScreenState();
}

class _CollectionSearchScreenState extends State<CollectionSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  String _query = '';
  bool _loading = false;
  String? _error;
  List<ArchiveCollection> _results = const [];

  bool _initialSearchDone = false;

  @override
  void initState() {
    super.initState();
    widget.activateTrigger?.addListener(_maybeRunInitialSearch);
    if (widget.activateTrigger?.value == true) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeRunInitialSearch(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    widget.activateTrigger?.removeListener(_maybeRunInitialSearch);
    super.dispose();
  }

  void _maybeRunInitialSearch() {
    if (_initialSearchDone) return;
    if (widget.activateTrigger?.value == true) {
      _initialSearchDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSearch('');
      });
    }
  }

  Future<void> _runSearch(String q) async {
    q = q.trim();
    if (q == _query && _results.isNotEmpty) return;

    final cached = await _SearchCache.get(q);
    if (cached != null) {
      setState(() {
        _query = q;
        _results = cached;
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _results = const [];
    });

    try {
      final res = await ArchiveApi.searchCollections(q);
      await _SearchCache.set(q, res);
      setState(() => _results = res);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _results = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ArchiveCollection c) async {
    await RecentProgressService.instance.touch(
      id: c.identifier,
      title: c.title.isNotEmpty ? c.title : c.identifier,
      thumb:
          c.thumbnailUrl ?? 'https://archive.org/services/img/${c.identifier}',
      kind: 'collection',
    );

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => CollectionDetailScreen(
              categoryName: c.title.isNotEmpty ? c.title : c.identifier,
              customQuery: 'collection:${c.identifier}',
            ),
      ),
    );
  }

  Future<void> _togglePin(String identifier) async {
    final store = CollectionStore();
    if (store.pinnedIds.contains(identifier)) {
      await store.unpin(identifier);
    } else {
      await store.pin(identifier);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = CollectionStore();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search collections'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            // Search Field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onSubmitted: _runSearch,
                decoration: InputDecoration(
                  hintText: 'Search metadata',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon:
                      _query.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              _runSearch('');
                              _focus.requestFocus();
                            },
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            // Results
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _runSearch(_query),
                child:
                    _results.isEmpty && !_loading && _error == null
                        ? _buildEmptyState()
                        : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: _results.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = _results[i];
                            final pinned = store.pinnedIds.contains(
                              c.identifier,
                            );

                            return _CollectionCard(
                              collection: c,
                              pinned: pinned,
                              onTap: () => _open(c),
                              onPinToggle: () => _togglePin(c.identifier),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.manage_search, size: 48),
        const SizedBox(height: 8),
        const Center(child: Text('No collections found')),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children:
              const [
                'subject:cartoons',
                'creator:prelinger',
                'language:eng',
                'year:1950..1960',
                'identifier:classic_tv',
                'subject:horror',
              ].map(_QuickChip.new).toList(),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── CARD ──────────────────────────────────────────────────────────────
class _CollectionCard extends StatelessWidget {
  final ArchiveCollection collection;
  final bool pinned;
  final VoidCallback? onTap;
  final VoidCallback? onPinToggle;

  const _CollectionCard({
    required this.collection,
    required this.pinned,
    this.onTap,
    this.onPinToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child:
                      collection.thumbnailUrl != null
                          ? CachedNetworkImage(
                            imageUrl: collection.thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder:
                                (_, __) => const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                            errorWidget:
                                (_, __, ___) => const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                ),
                          )
                          : Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.collections,
                              color: Colors.grey,
                            ),
                          ),
                ),
              ),
              const SizedBox(width: 16),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.title.isNotEmpty
                          ? collection.title
                          : collection.identifier,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${collection.downloads} downloads',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'In progress',
                        style: TextStyle(
                          color: Colors.green[800],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Pin Button
              if (onPinToggle != null)
                TextButton.icon(
                  onPressed: onPinToggle,
                  icon: Icon(
                    pinned ? Icons.check_circle : Icons.push_pin_outlined,
                    size: 20,
                  ),
                  label: Text(pinned ? 'Pinned' : 'Pin'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── QUICK CHIPS ───────────────────────────────────────────────────────
class _QuickChip extends StatelessWidget {
  final String q;
  const _QuickChip(this.q);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(q),
      onPressed: () {
        final state =
            context.findAncestorStateOfType<_CollectionSearchScreenState>()!;
        state._controller.text = q;
        state._runSearch(q);
      },
    );
  }
}
