import 'package:archivereader/services/recent_progress_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'archive_api.dart';
import 'collection_detail_screen.dart';
import 'collection_store.dart';
import 'main.dart'; // For RootShell.switchToTab

class PinnedCollectionsScreen extends StatefulWidget {
  const PinnedCollectionsScreen({super.key});

  @override
  State<PinnedCollectionsScreen> createState() =>
      _PinnedCollectionsScreenState();
}

class _PinnedCollectionsScreenState extends State<PinnedCollectionsScreen> {
  CollectionsHomeState? _store; // ← Nullable now
  List<ArchiveCollection> _collections = [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ← SAFE: Context is ready, inherited widgets are available
    final store = CollectionsHomeScope.of(context);
    if (_store != store) {
      _store?.removeListener(_onStoreChanged);
      _store = store;
      _store!.addListener(_onStoreChanged);
      _loadPinnedCollections();
    }
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) _loadPinnedCollections();
  }

  Future<void> _loadPinnedCollections() async {
    if (_store == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<ArchiveCollection> loaded = [];
      for (final id in _store!.pins) {
        try {
          final col = await ArchiveApi.getCollection(id);
          loaded.add(col);
        } catch (_) {
          // Skip failed
        }
      }
      if (mounted) {
        setState(() {
          _collections = loaded;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load pinned collections';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCollection(ArchiveCollection c) async {
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

  Future<void> _unpinCollection(String id, int index) async {
    final removed = _collections[index];
    setState(() {
      _collections.removeAt(index);
    });

    final snack = SnackBar(
      content: Text('Unpinned "${removed.title ?? removed.identifier}"'),
      action: SnackBarAction(label: 'Undo', onPressed: () => _store?.pin(id)),
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);

    await _store?.unpin(id);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _collections.isEmpty && !_loading && _error == null;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadPinnedCollections,
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildErrorState()
                : isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _collections.length,
                  itemBuilder: (context, i) {
                    final c = _collections[i];
                    return _PinnedCollectionTile(
                      collection: c,
                      onTap: () => _openCollection(c),
                      onDelete: () => _unpinCollection(c.identifier, i),
                    );
                  },
                ),
      ),
      floatingActionButton:
          _collections.isEmpty
              ? null
              : FloatingActionButton(
                onPressed: _loadPinnedCollections,
                child: const Icon(Icons.refresh),
              ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.push_pin_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'No pinned collections',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Search for collections and tap the pin icon to save them here.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () => RootShell.switchToTab(1),
          icon: const Icon(Icons.search),
          label: const Text('Search Collections'),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.warning_amber_rounded, size: 64),
        const SizedBox(height: 16),
        Text(
          'Failed to load',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _loadPinnedCollections,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

class _PinnedCollectionTile extends StatelessWidget {
  final ArchiveCollection collection;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PinnedCollectionTile({
    required this.collection,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Dismissible(
          key: ValueKey(collection.identifier),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => onDelete(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child:
                        collection.thumbnailUrl != null
                            ? CachedNetworkImage(
                              imageUrl: collection.thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder:
                                  (_, __) => Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.image,
                                      color: Colors.grey,
                                    ),
                                  ),
                              errorWidget:
                                  (_, __, ___) => Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image),
                                  ),
                            )
                            : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.collections),
                            ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.title.isNotEmpty
                            ? collection.title
                            : collection.identifier,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${collection.downloads} downloads',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.push_pin,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
