// path: lib/screens/favourites_screen.dart
import 'package:archivereader/screens/archive_item_screen.dart';
import 'package:archivereader/services/favourites_service.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/ui/capsule_theme.dart';
import 'package:archivereader/widgets/capsule_thumb_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../archive_api.dart';
import '../media/media_player_ops.dart';
import '../services/thumbnail_service.dart';
import '../utils/archive_helpers.dart';
import '../widgets/audio_chooser.dart';
import '../widgets/video_chooser.dart';
import 'audio_album_screen.dart';
import 'collection_detail_screen.dart';

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

        // Treat 'Favourites' as internal; UI default is always 'All'
        String selectedFolder;
        if (initialFolder != null &&
            initialFolder!.isNotEmpty &&
            initialFolder != 'Favourites') {
          selectedFolder = initialFolder!;
        } else {
          selectedFolder = 'All';
        }

        final items =
            selectedFolder == 'All'
                ? svc.allItems
                : svc.itemsIn(selectedFolder);

        return Scaffold(
          appBar: AppBar(
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _FolderSelector(
                  folders: folders,
                  currentFolder: selectedFolder,
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
          ),
          body: _GridBody(folderName: selectedFolder, items: items),
        );
      },
    );
  }
}

String _sanitizeArchiveId(String id) {
  var s = id.trim();
  if (s.startsWith('metadata/')) s = s.substring('metadata/'.length);
  if (s.startsWith('details/')) s = s.substring('details/'.length);
  return s;
}

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

  Future<void> _showMetadataSheet(FavoriteItem item) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FavoriteMetadataSheet(item: item),
    );
  }

  /// Resolve real mediatype from Archive.org and persist it (once).
  Future<String?> _resolveAndPersistMediaType(
    String id,
    FavoriteItem fav,
  ) async {
    final cached = fav.mediatype?.trim();
    if (cached != null && cached.isNotEmpty) return cached.toLowerCase();

    try {
      final meta = await ArchiveApi.getMetadata(id);
      final raw = Map<String, dynamic>.from(meta['metadata'] ?? {});
      final resolved = (raw['mediatype'] ?? '').toString().trim().toLowerCase();
      if (resolved.isNotEmpty &&
          resolved != (fav.mediatype ?? '').toLowerCase()) {
        final corrected = fav.copyWith(mediatype: resolved);
        await FavoritesService.instance.addToFolder(
          widget.folderName,
          corrected,
        );
      }
      return resolved.isEmpty ? null : resolved;
    } catch (_) {
      return null;
    }
  }

  // ---------- Helpers for file enrichment ----------
  String _inferFormat(String name, String? fmt) {
    final f = (fmt ?? '').trim().toLowerCase();
    if (f.isNotEmpty) return f;
    final m = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(name);
    return (m?.group(1) ?? '').toLowerCase();
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  bool _needsEnrichment(List<Map<String, String>> files) {
    if (files.isEmpty) return true;

    int valid = 0;
    for (final f in files) {
      final name = (f['name'] ?? '').trim();
      final fmt = (f['format'] ?? '').trim();
      final size = (f['size'] ?? '').trim();

      if (name.isEmpty) continue;

      final hasFormat =
          fmt.isNotEmpty ||
          RegExp(r'\.[a-z0-9]+$', caseSensitive: false).hasMatch(name);
      final hasSize = size.isEmpty || int.tryParse(size) != null;

      if (hasFormat && hasSize) valid++;
    }

    return valid < (files.length * 0.5);
  }

  List<Map<String, String>> _mapFilesForCache(List<Map<String, String>> files) {
    return files
        .where((f) => (f['name'] ?? '').toString().trim().isNotEmpty)
        .map((f) {
          final name = (f['name'] ?? '').toString();
          final fmt = _inferFormat(name, f['format']);
          final size = (f['size'] ?? '').toString();
          final width = (f['width'] ?? '').toString();
          final height = (f['height'] ?? '').toString();
          return <String, String>{
            'name': name,
            'format': fmt,
            if (size.trim().isNotEmpty) 'size': size,
            if (width.trim().isNotEmpty) 'width': width,
            if (height.trim().isNotEmpty) 'height': height,
          };
        })
        .toList(growable: false);
  }

  Future<void> _handleTap(FavoriteItem fav) async {
    final id = _sanitizeArchiveId(fav.id);
    final title = fav.title.trim().isNotEmpty ? fav.title.trim() : id;
    final thumb =
        fav.thumb?.trim().isNotEmpty == true
            ? fav.thumb!.trim()
            : archiveThumbUrl(id);

    // ────────────────────────────────────────────────
    // 0) FAST PATH: Use cached files to open video chooser
    //    → No network calls here.
    // ────────────────────────────────────────────────
    List<Map<String, String>> files = fav.files ?? [];

    List<Map<String, dynamic>> buildVideoFiles(List<Map<String, String>> src) {
      return src
          .where((f) {
            final name = (f['name'] ?? '').toString();
            if (name.isEmpty) return false;
            final url =
                'https://archive.org/download/$id/${Uri.encodeComponent(name)}';
            return MediaPlayerOps.isVideoUrl(url);
          })
          .map((f) {
            final name = (f['name'] ?? '').toString();
            final fmt = _inferFormat(name, (f['format'] ?? '').toString());
            return {
              'name': name,
              'format': fmt,
              'size': _toInt(f['size']),
              'width': _toInt(f['width']),
              'height': _toInt(f['height']),
            };
          })
          .toList(growable: false);
    }

    final fastVideoFiles = buildVideoFiles(files);
    if (fastVideoFiles.isNotEmpty) {
      // Log progress quickly without needing mediatype / isCollection.
      await RecentProgressService.instance.touch(
        id: id,
        title: title,
        thumb: thumb,
        kind: 'item', // or 'video' if your app supports that
      );
      if (!mounted) return;

      await showVideoChooser(
        context,
        identifier: id,
        title: title,
        files: fastVideoFiles,
      );
      return;
    }

    // ────────────────────────────────────────────────
    // 1) Resolve mediatype & collection status (slow path)
    //    Only for non-video items or when we lack cached video info.
    // ────────────────────────────────────────────────
    final mediatype = await _resolveAndPersistMediaType(id, fav);
    final mt = (mediatype ?? '').toLowerCase();

    final isCollection = await ArchiveApi.isCollection(id);

    final kindForProgress =
        isCollection
            ? 'collection'
            : (mt == 'audio' || mt == 'etree')
            ? 'audio'
            : 'item';

    await RecentProgressService.instance.touch(
      id: id,
      title: title,
      thumb: thumb,
      kind: kindForProgress,
    );
    if (!mounted) return;

    // ────────────────────────────────────────────────
    // 2) COLLECTION PATH
    // ────────────────────────────────────────────────
    if (isCollection) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: title,
                customQuery: 'collection:$id',
              ),
        ),
      );
      return;
    }

    // ────────────────────────────────────────────────
    // 3) Load / enrich files
    // ────────────────────────────────────────────────
    files = fav.files ?? [];

    if (_needsEnrichment(files)) {
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fetching file info…')));

        final fetched = await ArchiveApi.fetchFilesForIdentifier(id);
        final normalized = fetched
            .map((e) => Map<String, String>.from(e))
            .toList(growable: false);
        files = _mapFilesForCache(normalized);

        final updated = fav.copyWith(files: files, mediatype: mediatype);
        await FavoritesService.instance.addToFolder(widget.folderName, updated);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn’t fetch files: ${e.toString().split('\n').first}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    // ────────────────────────────────────────────────
    // 4) VIDEO: Slow-path (if we had no cached video files)
    // ────────────────────────────────────────────────
    final videoFiles = buildVideoFiles(files);
    if (videoFiles.isNotEmpty) {
      await showVideoChooser(
        context,
        identifier: id,
        title: title,
        files: videoFiles,
      );
      return;
    }

    // ────────────────────────────────────────────────
    // 5) AUDIO: unchanged
    // ────────────────────────────────────────────────
    final List<Map<String, dynamic>> audioFiles = files
        .where((f) {
          final name = (f['name'] ?? '').toString().toLowerCase();
          return MediaPlayerOps.isAudioUrl(name);
        })
        .map(
          (f) => {
            'name': f['name']!,
            'format': f['format'] ?? '',
            'size': _toInt(f['size']),
          },
        )
        .toList(growable: false);

    if (audioFiles.isNotEmpty) {
      final chosenExt = await showAudioFormatChooser(
        context,
        identifier: id,
        title: title,
        files: audioFiles,
      );

      if (!mounted) return;

      final filtered =
          (chosenExt == null)
              ? audioFiles
              : audioFiles.where((f) {
                final name = (f['name'] ?? '').toString().toLowerCase();
                return name.endsWith(chosenExt.toLowerCase());
              }).toList();

      final effectiveFiles = filtered.isNotEmpty ? filtered : audioFiles;

      final audioList =
          effectiveFiles
              .map<Map<String, String>>((f) => {'name': f['name'] as String})
              .toList();

      await RecentProgressService.instance.touch(
        id: id,
        title: title,
        thumb: thumb,
        kind: 'audio',
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => AudioAlbumScreen(
                identifier: id,
                title: title,
                files: audioList,
                thumbUrl: thumb,
              ),
        ),
      );

      return;
    }

    // ────────────────────────────────────────────────
    // 6) DEFAULT: File Browser
    // ────────────────────────────────────────────────
    await _openItemScreen(
      context,
      id: id,
      title: title,
      files: files,
      thumb: thumb,
    );
  }

  Future<void> _openItemScreen(
    BuildContext context, {
    required String id,
    required String title,
    required List<Map<String, String>> files,
    required String thumb,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ArchiveItemScreen(
              title: title,
              identifier: id,
              files: files,
              parentThumbUrl: thumb,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            childAspectRatio: 0.52,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final fav = widget.items[i];
            final id = _sanitizeArchiveId(fav.id);
            final title = fav.title.trim().isEmpty ? id : fav.title.trim();
            final thumb =
                fav.thumb?.trim().isNotEmpty == true
                    ? fav.thumb!.trim()
                    : archiveThumbUrl(id);

            // Check for playable media (audio or video)
            final hasMedia = (fav.files ?? []).any((f) {
              final name = f['name'] ?? '';
              if (name.isEmpty) return false;
              final url =
                  'https://archive.org/download/$id/${Uri.encodeComponent(name)}';
              return MediaPlayerOps.isVideoUrl(url) ||
                  MediaPlayerOps.isAudioUrl(url);
            });

            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(kCapsuleRadius),
                onTap: () => _handleTap(fav),
                onLongPress: () => _showMetadataSheet(fav),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔽 FIXED-SIZE THUMBNAIL (no Expanded)
                    AspectRatio(
                      aspectRatio: 2 / 3, // 3:4 cover art
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
                          if (hasMedia)
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

                    // 🔽 FIXED HEIGHT FOR UP TO ~2 LINES
                    SizedBox(
                      height: 40, // tweak if you change font size
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
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

// ──────────────────────── FILE TYPE CHOOSER ────────────────────────
class _FileTypeChooser extends StatelessWidget {
  final bool hasVideo;
  final bool hasAudio;
  final bool hasFiles;

  const _FileTypeChooser({
    required this.hasVideo,
    required this.hasAudio,
    required this.hasFiles,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open with'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasVideo)
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video Player'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          if (hasAudio)
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: const Text('Audio Player'),
              onTap: () => Navigator.pop(context, 'audio'),
            ),
          if (hasFiles)
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('File Browser'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ──────────────────────── AUDIO FILE CHOOSER ────────────────────────
class _AudioFileChooser extends StatelessWidget {
  final String identifier;
  final String title;
  final List<Map<String, dynamic>> files;
  final String thumb;

  const _AudioFileChooser({
    required this.identifier,
    required this.title,
    required this.files,
    required this.thumb,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Play Audio', style: Theme.of(context).textTheme.titleMedium),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (ctx, i) {
            final f = files[i];
            final name = f['name'] as String;
            final size = f['size'] as int?;
            final fmt = (f['format'] as String?)?.toUpperCase() ?? '';
            final duration = f['length']?.toString();

            return ListTile(
              leading: const Icon(Icons.audiotrack),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  if (fmt.isNotEmpty) fmt,
                  if (size != null) _formatBytes(size),
                  if (duration != null) duration,
                ].join(' • '),
              ),
              onTap: () {
                final url =
                    'https://archive.org/download/$identifier/${Uri.encodeComponent(name)}';
                Navigator.pop(ctx);
                MediaPlayerOps.playAudio(
                  ctx,
                  url: url,
                  identifier: identifier,
                  title: title,
                  thumb: thumb,
                  fileName: name,
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ──────────────────────── REST OF FILE ────────────────────────

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

class _FolderSelector extends StatelessWidget {
  final String currentFolder;
  final ValueChanged<String> onChanged;
  final List<String> folders;

  const _FolderSelector({
    required this.currentFolder,
    required this.onChanged,
    required this.folders,
  });

  @override
  Widget build(BuildContext context) {
    // Hide the internal 'Favourites' folder; use 'All' as the main view.
    final items =
        <String>{'All', ...folders.where((f) => f != 'Favourites')}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // If for some reason currentFolder is no longer in the list (e.g. 'Favourites'),
    // fall back to 'All' so the UI stays valid.
    final effectiveCurrent =
        items.contains(currentFolder) ? currentFolder : 'All';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showFolderSheet(context, items, effectiveCurrent),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: 'Favourites folder',
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          effectiveCurrent,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _showFolderSheet(
    BuildContext context,
    List<String> items,
    String effectiveCurrent,
  ) async {
    final svc = FavoritesService.instance;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Choose folder'),
                  subtitle: Text(
                    'Swipe left to delete a folder',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final folder = items[index];
                      final canDelete =
                          folder != 'All' && folder != 'Favourites';

                      return Dismissible(
                        key: ValueKey(folder),
                        direction:
                            canDelete
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          color: theme.colorScheme.error,
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss:
                            canDelete
                                ? (direction) async {
                                  final confirmed = await showDialog<bool>(
                                    context: sheetCtx,
                                    builder:
                                        (ctx) => AlertDialog(
                                          title: const Text('Delete folder?'),
                                          content: Text(
                                            'Delete the "$folder" folder and remove '
                                            'all favourites inside it?\n\n'
                                            'Items that also exist in other folders '
                                            'will stay there.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () =>
                                                      Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () =>
                                                      Navigator.pop(ctx, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                  );

                                  if (confirmed == true) {
                                    await svc.deleteFolder(folder);

                                    // If we just deleted the active folder,
                                    // jump back to "All"
                                    if (effectiveCurrent == folder) {
                                      Navigator.of(
                                        sheetCtx,
                                      ).pop(); // close sheet
                                      onChanged('All');
                                    } else {
                                      // Just close the sheet; parent will rebuild
                                      Navigator.of(sheetCtx).pop();
                                    }
                                  }

                                  // We close the sheet manually; don't let
                                  // Dismissible animate it away.
                                  return false;
                                }
                                : null,
                        child: ListTile(
                          title: Text(folder),
                          onTap: () {
                            Navigator.of(sheetCtx).pop();
                            if (folder != effectiveCurrent) {
                              onChanged(folder);
                            }
                          },
                        ),
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

// ── Metadata Sheet with TMDb enrichment ────────────────────────────
class _FavoriteMetadataSheet extends StatefulWidget {
  final FavoriteItem item;
  const _FavoriteMetadataSheet({required this.item});

  @override
  State<_FavoriteMetadataSheet> createState() => _FavoriteMetadataSheetState();
}

class _FavoriteMetadataSheetState extends State<_FavoriteMetadataSheet> {
  late Future<Map<String, dynamic>> _future;

  Map<String, String>? _enrichedOverrides;
  bool _enriching = false;

  @override
  void initState() {
    super.initState();
    _future = ArchiveApi.getMetadata(_sanitizeArchiveId(widget.item.id));
  }

  Future<void> _retry() async {
    setState(() {
      _future = ArchiveApi.getMetadata(_sanitizeArchiveId(widget.item.id));
    });
  }

  Future<void> _enrichWithTmdb({
    required String cleanId,
    required Map<String, dynamic> meta,
  }) async {
    if (!mounted || _enriching) return;

    setState(() => _enriching = true);

    try {
      // Build the same kind of map you use in CollectionDetailScreen
      final base = <String, String>{
        'identifier': cleanId,
        'title': _flat(meta['title']),
        'description': _flat(meta['description']),
        'creator': _flat(meta['creator']),
        'subject': _flat(meta['subject']),
        'year': _flat(meta['year']),
        'mediatype': _flat(meta['mediatype']),
        'thumb':
            (widget.item.thumb?.trim().isNotEmpty == true)
                ? widget.item.thumb!.trim()
                : archiveThumbUrl(cleanId),
      };

      // 🔮 Ask TMDb to enrich this map
      await ThumbnailService().enrichItemWithTmdb(base);

      // Store enriched values in state so the UI can use them
      setState(() {
        _enrichedOverrides = base;
      });

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Metadata enriched via TMDb')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Failed to enrich metadata: $e')));
    } finally {
      if (mounted) {
        setState(() => _enriching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load metadata',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                );
              }

              final raw = snapshot.data ?? const <String, dynamic>{};
              final meta = Map<String, dynamic>.from(
                (raw['metadata'] as Map?) ?? const <String, dynamic>{},
              );
              final overrides = _enrichedOverrides;

              // Base values from Archive.org
              final baseTitle = _flat(meta['title']).trim();
              final baseDescription = _flat(meta['description']).trim();
              final baseCreator = _flat(meta['creator']).trim();
              final baseYear = _flat(meta['year']).trim();
              final baseMediatype = _flat(meta['mediatype']).trim();
              final baseLanguage = _flat(meta['language']).trim();
              final baseRuntime =
                  _flat(meta['runtime']).trim().isNotEmpty
                      ? _flat(meta['runtime']).trim()
                      : _flat(meta['length']).trim();
              final baseDownloads = _flat(meta['downloads']).trim();
              String added = _flat(meta['publicdate']).trim();
              if (added.isEmpty) added = _flat(meta['date']).trim();
              if (added.isEmpty) added = _flat(meta['addeddate']).trim();

              final cleanId = _sanitizeArchiveId(widget.item.id);

              // Collections / formats / subjects & cached files
              final subjects = _asList(meta['subject'])
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

              final formatSet = <String>{
                ...widget.item.formats
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty),
                ..._asList(meta['format']),
              };

              final cachedFormats =
                  widget.item.files
                      ?.map((f) => (f['fmt'] ?? f['format'] ?? '').toString())
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList() ??
                  const <String>[];

              formatSet.addAll(cachedFormats);

              final formats =
                  formatSet.toList()..sort(
                    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                  );

              final collections = _asList(meta['collection'])
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

              final cachedFilesCount = widget.item.files?.length ?? 0;

              // Prefer enriched overrides if present
              final title =
                  (overrides?['title']?.trim().isNotEmpty == true)
                      ? overrides!['title']!.trim()
                      : baseTitle.isNotEmpty
                      ? baseTitle
                      : widget.item.title;

              final description =
                  (overrides?['description']?.trim().isNotEmpty == true)
                      ? overrides!['description']!.trim()
                      : baseDescription;

              final creator =
                  (overrides?['creator']?.trim().isNotEmpty == true)
                      ? overrides!['creator']!.trim()
                      : baseCreator;

              final year =
                  (overrides?['year']?.trim().isNotEmpty == true)
                      ? overrides!['year']!.trim()
                      : baseYear;

              final mediatype =
                  (widget.item.mediatype?.trim().isNotEmpty == true)
                      ? widget.item.mediatype!.trim()
                      : (overrides?['mediatype']?.trim().isNotEmpty == true)
                      ? overrides!['mediatype']!.trim()
                      : baseMediatype;

              final language = baseLanguage;
              final runtime = baseRuntime;
              final downloads = baseDownloads;

              final cleanThumb =
                  (widget.item.thumb?.trim().isNotEmpty == true)
                      ? widget.item.thumb!.trim()
                      : archiveThumbUrl(cleanId);

              final thumb =
                  (overrides?['thumb']?.trim().isNotEmpty == true)
                      ? overrides!['thumb']!.trim()
                      : cleanThumb;

              final url =
                  (widget.item.url?.trim().isNotEmpty == true)
                      ? widget.item.url!.trim()
                      : 'https://archive.org/details/$cleanId';

              // Info chips
              final infoChips = <Widget>[];
              if (mediatype.isNotEmpty) {
                infoChips.add(_buildInfoChip(theme, mediatype));
              }
              if (year.isNotEmpty) {
                infoChips.add(_buildInfoChip(theme, 'Year $year'));
              }
              if (language.isNotEmpty) {
                infoChips.add(_buildInfoChip(theme, language));
              }
              if (runtime.isNotEmpty) {
                infoChips.add(_buildInfoChip(theme, runtime));
              }
              if (downloads.isNotEmpty) {
                infoChips.add(_buildInfoChip(theme, '$downloads downloads'));
              }
              if (cachedFilesCount > 0) {
                final label =
                    'Cached $cachedFilesCount file${cachedFilesCount == 1 ? '' : 's'}';
                infoChips.add(_buildInfoChip(theme, label));
              }

              // Main rows (with Enhance button at the top)
              final infoRows = <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon:
                        _enriching
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.auto_awesome),
                    label: Text(
                      _enrichedOverrides == null
                          ? 'Enhance metadata'
                          : 'Re-run enhancement',
                    ),
                    onPressed:
                        _enriching
                            ? null
                            : () =>
                                _enrichWithTmdb(cleanId: cleanId, meta: meta),
                  ),
                ),
                const SizedBox(height: 12),

                if (creator.isNotEmpty)
                  _buildInfoRow(theme, 'Creator', creator),
                if (added.isNotEmpty) _buildInfoRow(theme, 'Published', added),
                if (collections.isNotEmpty)
                  _buildChipSection(
                    theme,
                    'Collections',
                    collections,
                    icon: Icons.folder_open,
                  ),
                if (formats.isNotEmpty)
                  _buildChipSection(
                    theme,
                    'Formats',
                    formats,
                    icon: Icons.download_rounded,
                  ),
                if (subjects.isNotEmpty)
                  _buildChipSection(
                    theme,
                    'Subjects',
                    subjects,
                    icon: Icons.label_outline,
                    limit: 18,
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(
                      theme,
                      'Description',
                      icon: Icons.notes_rounded,
                    ),
                    description.isNotEmpty
                        ? SelectableText(
                          description,
                          style: theme.textTheme.bodyMedium,
                        )
                        : Text(
                          'No description available.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _openExternal(url),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open on Archive.org'),
                ),
                if (cachedFilesCount > 0)
                  () {
                    final cachedList =
                        widget.item.files!
                            .map(
                              (f) =>
                                  (f['pretty'] ?? f['name'] ?? '').toString(),
                            )
                            .where((name) => name.trim().isNotEmpty)
                            .toList();
                    return cachedList.isNotEmpty
                        ? Column(
                          children: [
                            const SizedBox(height: 16),
                            _buildChipSection(
                              theme,
                              'Cached downloads',
                              cachedList,
                              icon: Icons.offline_pin,
                              limit: 12,
                            ),
                          ],
                        )
                        : const SizedBox.shrink();
                  }(),
              ];

              return ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: CapsuleThumbCard(
                          heroTag: 'fav-meta:${widget.item.id}',
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildIdentifierRow(theme, cleanId),
                            if (infoChips.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: infoChips,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ...infoRows,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _flat(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value
          .where((e) => e != null)
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .join(', ');
    }
    return value.toString();
  }

  List<String> _asList(dynamic value) {
    final result = <String>[];
    void addValue(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || result.contains(trimmed)) return;
      result.add(trimmed);
    }

    if (value == null) return result;
    if (value is List) {
      for (final entry in value) {
        if (entry == null) continue;
        addValue(entry.toString());
      }
      return result;
    }
    value.toString().split(RegExp(r'[;,]')).forEach(addValue);
    return result;
  }

  Widget _buildSectionTitle(ThemeData theme, String label, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildChipSection(
    ThemeData theme,
    String label,
    List<String> values, {
    IconData? icon,
    int? limit,
  }) {
    if (values.isEmpty) return const SizedBox.shrink();
    final maxCount = limit ?? values.length;
    final visible = values.take(maxCount).toList();
    final remaining = values.length - visible.length;
    if (remaining > 0) visible.add('+ $remaining more');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(theme, label, icon: icon),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible
                .map((v) => Chip(label: Text(v)))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentifierRow(ThemeData theme, String id) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            id,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy identifier',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: id));
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Identifier copied to clipboard')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoChip(ThemeData theme, String label) {
    return Chip(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      label: Text(label),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }
}
