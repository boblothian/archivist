// lib/screens/favourites_screen.dart
import 'package:archivereader/services/downloads_service.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/utils/open_archive_item.dart'; // for showVideoFileChooser
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'archive_api.dart';
import 'utils/archive_helpers.dart';
import 'utils/external_launch.dart';

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
            final thumb =
                fav.thumb?.trim().isNotEmpty == true
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

                  // 1. Use cached files if available
                  final cachedFiles = fav.files;
                  if (cachedFiles != null && cachedFiles.isNotEmpty) {
                    await _openFileChooser(
                      context: context,
                      identifier: id,
                      title: title,
                      files: cachedFiles,
                      thumb: thumb,
                    );
                    return;
                  }

                  // 2. Fetch from network, cache, then open
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Loading files...')),
                  );

                  try {
                    final files = await ArchiveApi.fetchFilesForIdentifier(id);
                    if (files.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No downloadable files found'),
                        ),
                      );
                      return;
                    }

                    // Cache files
                    final updated = fav.copyWith(files: files);
                    await svc.addToFolder(widget.folderName, updated);

                    if (!context.mounted) return;

                    await _openFileChooser(
                      context: context,
                      identifier: id,
                      title: title,
                      files: files,
                      thumb: thumb,
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to load files: ${e.toString().split('\n').first}',
                        ),
                        backgroundColor: Colors.red,
                      ),
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
                          // Optional: "READY" badge when files are cached
                          if (fav.files != null && fav.files!.isNotEmpty)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'READY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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

// ── File Chooser (PDF/EPUB/CBZ + Videos) ─────────────────────────────
Future<void> _openFileChooser({
  required BuildContext context,
  required String identifier,
  required String title,
  required List<Map<String, String>> files,
  String? thumb,
}) async {
  final thumbUrl = thumb ?? archiveThumbUrl(identifier);

  // Detect if all files are videos → use existing video chooser
  final videoFiles =
      files.where((f) {
        final name = (f['name'] ?? '').toLowerCase();
        return [
          'mp4',
          'm4v',
          'webm',
          'mkv',
          'm3u8',
          'avi',
          'mov',
        ].any(name.endsWith);
      }).toList();

  if (videoFiles.isNotEmpty && videoFiles.length == files.length) {
    await showVideoFileChooser(
      context: context,
      identifier: identifier,
      title: title,
      videoOptions: videoFiles,
      thumbForId: (_) => thumbUrl,
    );
    return;
  }

  // Otherwise: show generic file chooser
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (_) => _FileChooserSheet(
          identifier: identifier,
          title: title,
          files: files,
          thumb: thumbUrl,
        ),
  );
}

class _FileChooserSheet extends StatelessWidget {
  final String identifier;
  final String title;
  final List<Map<String, String>> files;
  final String thumb;

  const _FileChooserSheet({
    required this.identifier,
    required this.title,
    required this.files,
    required this.thumb,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Select a file to open or download'),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (_, i) {
                final f = files[i];
                final name = f['name'] ?? 'unknown';
                final size = f['size'] ?? '';
                final fmt = (f['fmt'] ?? '').toUpperCase();

                return FutureBuilder<bool>(
                  future: DownloadsService.instance.isDownloaded(identifier),
                  builder: (c, snap) {
                    final isDownloaded = snap.data == true;
                    return ListTile(
                      leading: Icon(_iconFor(name)),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '$fmt • $size${isDownloaded ? '  •  Downloaded' : ''}',
                        style: TextStyle(
                          color: isDownloaded ? Colors.green : null,
                          fontWeight: isDownloaded ? FontWeight.w600 : null,
                        ),
                      ),
                      trailing:
                          isDownloaded
                              ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                              : null,
                      onTap: () => _openFile(context, f),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (l.endsWith('.epub')) return Icons.book;
    if (l.endsWith('.cbz') || l.endsWith('.cbr'))
      return Icons.collections_bookmark;
    if (l.contains('mp4') || l.contains('webm') || l.contains('mkv'))
      return Icons.movie;
    return Icons.description;
  }

  Future<void> _openFile(BuildContext ctx, Map<String, String> file) async {
    Navigator.pop(ctx); // close sheet

    final url = file['url']!;
    final name = file['name']!;
    final mime = _mimeFor(name);

    // Update recent progress
    await RecentProgressService.instance.touch(
      id: identifier,
      title: title,
      thumb: thumb,
      kind: 'item',
      fileUrl: url,
      fileName: name,
    );

    // Ask: Browser or App?
    final choice = await showDialog<String>(
      context: ctx,
      builder:
          (d) => AlertDialog(
            title: const Text('Open file'),
            content: Text('Open “$name” with:'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, 'browser'),
                child: const Text('Browser'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(d, 'app'),
                child: const Text('Installed app'),
              ),
            ],
          ),
    );

    if (choice == null) return;

    if (choice == 'browser') {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      await openExternallyWithChooser(
        url: url,
        mimeType: mime,
        chooserTitle: 'Open with',
      );
    }
  }

  String _mimeFor(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.pdf')) return 'application/pdf';
    if (l.endsWith('.epub')) return 'application/epub+zip';
    if (l.endsWith('.cbz')) return 'application/vnd.comicbook+zip';
    if (l.endsWith('.cbr')) return 'application/vnd.comicbook+rar';
    if (l.contains('mp4')) return 'video/mp4';
    if (l.contains('webm')) return 'video/webm';
    if (l.contains('mkv')) return 'video/x-matroska';
    return '*/*';
  }
}
