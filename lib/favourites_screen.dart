// lib/screens/favourites_screen.dart
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:flutter/material.dart';

import 'archive_api.dart';
import 'archive_item_loader.dart';
import 'archive_item_screen.dart';
import 'collection_detail_screen.dart';
import 'utils/archive_helpers.dart';

class FavoritesScreen extends StatelessWidget {
  final String? initialFolder;

  const FavoritesScreen({super.key, this.initialFolder});

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesService.instance;

    return ValueListenableBuilder<int>(
      valueListenable: svc.version,
      builder: (context, _, __) {
        final folders = svc.folders();
        final selectedFolder = initialFolder ?? folders.firstOrNull ?? 'All';

        final items = selectedFolder == 'All'
            ? svc.allItems
            : svc.itemsIn(selectedFolder);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Favourites'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: _FolderSelector(
                folders: folders,
                selected: selectedFolder,
                onChanged: (folder) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => FavoritesScreen(initialFolder: folder),
                    ),
                  );
                },
              ),
            ),
          ),
          body: _GridBody(folderName: selectedFolder, items: items),
        );
      },
    );
  }
}

// ── Grid Body with capsule thumbs and delete "X" ──────────────────────────────
class _GridBody extends StatefulWidget {
  final String folderName;
  final List<FavoriteItem> items;

  const _GridBody({required this.folderName, required this.items});

  @override
  State<_GridBody> createState() => _GridBodyState();
}

class _GridBodyState extends State<_GridBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No favourites in this folder'),
          ],
        ),
      );
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final svc = FavoritesService.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = adaptiveCrossAxisCount(constraints.maxWidth);

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.72,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final fav = widget.items[i];
            final id = fav.id.trim();
            final title = fav.title.trim().isEmpty ? id : fav.title.trim();
            final thumb = fav.thumb?.trim().isNotEmpty == true
                ? fav.thumb!.trim()
                : archiveThumbUrl(id);

            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(kCapsuleRadius),
                onTap: () async {
                  await RecentProgressService.instance.touch(
                    id: id,
                    title: title,
                    thumb: thumb,
                    kind: 'item',
                  );

                  if (!context.mounted) return;

                  // FIXED: Handle nullable files
                  final cachedFiles = fav.files;
                  if (cachedFiles != null && cachedFiles.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArchiveItemScreen(
                          title: title,
                          identifier: id,
                          files: cachedFiles,
                        ),
                      ),
                    );
                    return;
                  }

                  // FALLBACK: fetch from network
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Loading files...')),
                  );

                  try {
                    final files = await fetchFilesForIdentifier(id);
                    if (files.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('No downloadable files found')),
                      );
                      return;
                    }

                    // Cache the files
                    final updated = fav.copyWith(files: files);
                    await svc.addToFolder(widget.folderName, updated);

                    if (!context.mounted) return;

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArchiveItemScreen(
                          title: title,
                          identifier: id,
                          files: files,
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to load files: $e')),
                    );
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CapsuleThumbCard(
                              heroTag: 'fav:$id',
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              fillParent: true,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _DeleteChip(
                              onDelete: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('Remove favourite?'),
                                    content: Text(
                                      'Remove "$title" from favourites?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dCtx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dCtx, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed != true) return;

                                await svc.remove(
                                  id,
                                  fromFolder: widget.folderName,
                                );
                                messenger?.showSnackBar(
                                  SnackBar(content: Text('Removed "$title"')),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Delete Chip ─────────────────────────────────────────────────────
class _DeleteChip extends StatelessWidget {
  final VoidCallback onDelete;
  const _DeleteChip({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onDelete,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: const Icon(Icons.close_rounded, size: 16),
      ),
    );
  }
}

// ── Folder Selector Dropdown ────────────────────────────────────────
class _FolderSelector extends StatelessWidget {
  final List<String> folders;
  final String selected;
  final ValueChanged<String> onChanged;

  const _FolderSelector({
    required this.folders,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'All', child: Text('All Favourites')),
      ...folders.map((f) => DropdownMenuItem(value: f, child: Text(f))),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButton<String>(
        value: selected,
        isExpanded: true,
        underline: const SizedBox(),
        items: items,
        onChanged: (v) => v != null ? onChanged(v) : null,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}