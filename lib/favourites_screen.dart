// lib/screens/favorites_screen.dart
import 'package:archivereader/archive_item_screen.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/widgets/favourite_add_dialogue.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'net.dart';

class FavoritesScreen extends StatefulWidget {
  final String? initialFolder;

  const FavoritesScreen({super.key, this.initialFolder});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late final ValueNotifier<int> _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = FavoritesService.instance.version;
    _notifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _notifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesService.instance;
    final folderName = widget.initialFolder ?? 'All';
    final items =
        widget.initialFolder != null
            ? svc.itemsIn(widget.initialFolder!)
            : svc.allItems;

    return Scaffold(
      appBar: AppBar(
        title: Text('Favorites: $folderName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add current item to another folder',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pick an item to add')),
              );
            },
          ),
        ],
      ),
      body: items.isEmpty ? _buildEmpty(folderName) : _buildList(items),
    );
  }

  Widget _buildEmpty(String folderName) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Folder "$folderName" is empty',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('Long-press any item in a collection to add it here.'),
        ],
      ),
    );
  }

  Widget _buildList(List<FavoriteItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return _FavoriteTile(item: item, folderName: widget.initialFolder);
      },
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  final FavoriteItem item;
  final String? folderName;

  const _FavoriteTile({required this.item, this.folderName});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            httpHeaders: Net.headers,
            imageUrl: item.thumb ?? '',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            placeholder:
                (_, __) => const SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            errorWidget:
                (_, __, ___) => const Icon(Icons.broken_image, size: 36),
          ),
        ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle:
            item.author != null
                ? Text(
                  item.author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
                : null,
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            final svc = FavoritesService.instance;
            if (action == 'remove') {
              if (folderName != null) {
                await svc.removeFromFolder(folderName!, item.id);
              } else {
                await svc.removeFromAllFolders(item.id);
              }
            } else if (action == 'move') {
              final folder = await showAddToFavoritesDialog(
                context,
                item: item,
              );
              if (folder != null) {
                await svc.addToFolder(folder, item);
                if (folderName != null) {
                  await svc.removeFromFolder(folderName!, item.id);
                } else {
                  await svc.removeFromAllFolders(item.id);
                }
              }
            }
          },
          itemBuilder:
              (_) => const [
                PopupMenuItem(value: 'remove', child: Text('Remove')),
                PopupMenuItem(value: 'move', child: Text('Move to…')),
              ],
        ),
        // ONLY CHANGE: opens the real file picker dialog
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => ArchiveItemScreen(
                    title: item.title,
                    identifier: item.id,
                    files: const [], // Will auto-fetch
                  ),
            ),
          );
        },
      ),
    );
  }
}
