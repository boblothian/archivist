// lib/screens/collection_search_screen.dart
import 'dart:async';

import 'package:archivereader/collection_store.dart'; // ← singleton store
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../archive_api.dart';
import 'collection_detail_screen.dart';

class CollectionSearchScreen extends StatefulWidget {
  /// Pass a notifier that flips to true the first time this tab/screen is shown.
  /// If null, the screen won't auto-run the empty search at all (only on user input).
  final ValueNotifier<bool>? activateTrigger;

  const CollectionSearchScreen({Key? key, this.activateTrigger})
    : super(key: key);

  @override
  State<CollectionSearchScreen> createState() => _CollectionSearchScreenState();
}

class _CollectionSearchScreenState extends State<CollectionSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  String _query = '';
  bool _loading = false;
  String? _error;
  List<ArchiveCollection> _results = const [];

  bool _initialSearchDone = false; // ← ensures we only auto-run once

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);

    // ← DO NOT run a search on init. This avoids startup network calls on iOS.
    // If a RootShell provides an activateTrigger, lazy-run once after the screen is actually shown.
    widget.activateTrigger?.addListener(_maybeRunInitialSearch);
    // If the trigger is already true by the time we build (e.g., direct navigation), handle it.
    if (widget.activateTrigger?.value == true) {
      // Schedule post-frame to avoid kicking work during build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeRunInitialSearch(),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    widget.activateTrigger?.removeListener(_maybeRunInitialSearch);
    super.dispose();
  }

  void _maybeRunInitialSearch() {
    if (_initialSearchDone) return;
    if (widget.activateTrigger?.value == true) {
      _initialSearchDone = true;
      // Run after this frame so we don’t contend with tab transition animations.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSearch('');
      });
    }
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _controller.text.trim();
      if (q == _query) return;
      // Only run when user actually changes text; this is user-driven and safe.
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final res = await ArchiveApi.searchCollections(q);
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
      title: c.title?.isNotEmpty == true ? c.title! : c.identifier,
      thumb:
          c.thumbnailUrl ?? 'https://archive.org/services/img/${c.identifier}',
      kind: 'collection',
    );

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => CollectionDetailScreen(
              categoryName:
                  c.title?.isNotEmpty == true ? c.title! : c.identifier,
              customQuery: 'collection:${c.identifier}',
            ),
      ),
    );
  }

  /// Pin / unpin using the singleton store
  Future<void> _togglePin(String identifier) async {
    final store = CollectionStore(); // direct singleton access

    if (store.pinnedIds.contains(identifier)) {
      await store.unpin(identifier);
    } else {
      await store.pin(identifier);
    }

    // UI updates automatically because the store is a ChangeNotifier
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = CollectionStore(); // current pin state

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
      body: Column(
        children: [
          // ── Search Field ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted:
                  _runSearch, // user-driven; fine to trigger immediately
              decoration: InputDecoration(
                hintText:
                    'Search metadata. Try: subject:cartoons  creator:prelinger  language:eng  year:1950..1960',
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

          // ── Error ───────────────────────────────────────────
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          // ── Results ────────────────────────────────────────
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
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _results[i];
                          final pinned = store.pinnedIds.contains(c.identifier);

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

/// ──────────────────────────────────────────────────────────────
///  CARD
/// ──────────────────────────────────────────────────────────────
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
              // ── Thumbnail ─────────────────────────────────────
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

              // ── Text ───────────────────────────────────────────
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
                    // Optional "In progress" badge – keep if you want
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

              // ── Pin Button ─────────────────────────────────────
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

/// ──────────────────────────────────────────────────────────────
///  QUICK SEARCH CHIPS
/// ──────────────────────────────────────────────────────────────
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
