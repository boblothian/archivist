// lib/screens/favourites_screen.dart
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:flutter/material.dart';

import 'archive_item_loader.dart';
import 'archive_item_screen.dart';

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

        // Get items for the selected folder
        final items =
            selectedFolder == 'All'
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
                  // Navigate to same screen with new folder
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

  String _thumbForId(String id) => 'https://archive.org/services/img/$id';

  int _computeCrossAxis(double w) {
    if (w >= 1280) return 6;
    if (w >= 1024) return 5;
    if (w >= 840) return 4;
    if (w >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

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
        final crossAxisCount = _computeCrossAxis(constraints.maxWidth);

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
            final thumb =
                fav.thumb?.trim().isNotEmpty == true
                    ? fav.thumb!.trim()
                    : _thumbForId(id);

            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(kCapsuleRadius),
                onTap: () async {
                  // 1. Update recent
                  await RecentProgressService.instance.touch(
                    id: id,
                    title: title,
                    thumb: thumb,
                    kind: 'auto',
                  );

                  // 2. Fetch file list
                  List<Map<String, String>> files;
                  try {
                    files = await fetchFilesForIdentifier(id);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to load item: $e')),
                    );
                    return;
                  }

                  // 3. Open real viewer
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => ArchiveItemScreen(
                            title: title,
                            identifier: id,
                            files: files,
                          ),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail + Delete X
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
                                  builder:
                                      (dCtx) => AlertDialog(
                                        title: const Text('Remove favourite?'),
                                        content: Text(
                                          'Remove "$title" from favourites?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () =>
                                                    Navigator.pop(dCtx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(dCtx, true),
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

// ── Delete Chip (unchanged) ─────────────────────────────────────
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

// ── Folder Selector Dropdown ─────────────────────────────────────
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
