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
import '../utils/archive_helpers.dart';

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

  /// Resolve real mediatype from Archive.org and persist it
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

  Future<void> _handleTap(FavoriteItem fav) async {
    final id = _sanitizeArchiveId(fav.id);
    final title = fav.title.trim().isEmpty ? id : fav.title.trim();
    final thumb =
        fav.thumb?.trim().isNotEmpty == true
            ? fav.thumb!.trim()
            : archiveThumbUrl(id);

    final mediatype = await _resolveAndPersistMediaType(id, fav);

    await RecentProgressService.instance.touch(
      id: id,
      title: title,
      thumb: thumb,
      kind:
          mediatype == 'collection' || mediatype == 'audio'
              ? 'collection'
              : 'item', // FIX: Treat audio as collection for progress
    );
    if (!mounted) return;

    // LOAD FILES FIRST (for all types)
    List<Map<String, String>> files = fav.files ?? [];
    if (files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Loading files...')));
      try {
        files = await ArchiveApi.fetchFilesForIdentifier(id);
        final updated = fav.copyWith(files: files, mediatype: mediatype);
        await FavoritesService.instance.addToFolder(widget.folderName, updated);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().split('\n').first}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    // VIDEO AUTOPLAY (if any videos found)
    final videoUrls =
        files
            .map((f) => f['name'] ?? '')
            .where((n) => n.isNotEmpty)
            .map(
              (n) =>
                  'https://archive.org/download/$id/${Uri.encodeComponent(n)}',
            )
            .where(MediaPlayerOps.isVideoUrl)
            .toList();
    final bestVideo = MediaPlayerOps.pickBestVideoUrl(videoUrls);
    if (bestVideo != null) {
      await MediaPlayerOps.playVideo(
        context,
        url: bestVideo,
        identifier: id,
        title: title,
      );
      return;
    }

    // ROUTE TO RIGHT SCREEN
    if (mediatype == 'collection' || mediatype == 'audio') {
      // FIX: Include 'audio'
      // For collections/audio: Use ArchiveItemScreen with files (shows MP3 grid)
      await _openItemScreen(
        context,
        id: id,
        title: title,
        files: files, // Already loaded — shows MP3s!
        thumb: thumb,
      );
    } else {
      // Single items (PDFs, etc.): Same screen
      await _openItemScreen(
        context,
        id: id,
        title: title,
        files: files,
        thumb: thumb,
      );
    }
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
            childAspectRatio: 0.72,
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

            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(kCapsuleRadius),
                onTap: () => _handleTap(fav),
                onLongPress: () => _showMetadataSheet(fav),
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

// FIXED: No more duplicate 'All', no unused param
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
    final items = <String>['All', ...folders].toSet().toList();

    return DropdownButton<String>(
      value: currentFolder,
      isExpanded: true,
      hint: const Text('Select folder'),
      items:
          items.map((folder) {
            return DropdownMenuItem<String>(
              value: folder,
              child: Text(folder, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
      onChanged: (value) => value != null ? onChanged(value) : null,
    );
  }
}

// ── Metadata Sheet (unchanged) ────────────────────────────
class _FavoriteMetadataSheet extends StatefulWidget {
  final FavoriteItem item;
  const _FavoriteMetadataSheet({required this.item});

  @override
  State<_FavoriteMetadataSheet> createState() => _FavoriteMetadataSheetState();
}

class _FavoriteMetadataSheetState extends State<_FavoriteMetadataSheet> {
  late Future<Map<String, dynamic>> _future;

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

              final title =
                  _flat(meta['title']).trim().isNotEmpty
                      ? _flat(meta['title']).trim()
                      : widget.item.title;
              final description = _flat(meta['description']).trim();
              final creator = _flat(meta['creator']).trim();
              final year = _flat(meta['year']).trim();
              final mediatype =
                  (widget.item.mediatype?.trim().isNotEmpty == true)
                      ? widget.item.mediatype!.trim()
                      : _flat(meta['mediatype']).trim();
              final language = _flat(meta['language']).trim();
              final runtime =
                  _flat(meta['runtime']).trim().isNotEmpty
                      ? _flat(meta['runtime']).trim()
                      : _flat(meta['length']).trim();
              final downloads = _flat(meta['downloads']).trim();
              String added = _flat(meta['publicdate']).trim();
              if (added.isEmpty) added = _flat(meta['date']).trim();
              if (added.isEmpty) added = _flat(meta['addeddate']).trim();

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
              final cleanId = _sanitizeArchiveId(widget.item.id);
              final thumb =
                  (widget.item.thumb?.trim().isNotEmpty == true)
                      ? widget.item.thumb!.trim()
                      : archiveThumbUrl(cleanId);
              final url =
                  (widget.item.url?.trim().isNotEmpty == true)
                      ? widget.item.url!.trim()
                      : 'https://archive.org/details/$cleanId';

              final infoChips = <Widget>[];
              if (mediatype.isNotEmpty)
                infoChips.add(_buildInfoChip(theme, mediatype));
              if (year.isNotEmpty)
                infoChips.add(_buildInfoChip(theme, 'Year $year'));
              if (language.isNotEmpty)
                infoChips.add(_buildInfoChip(theme, language));
              if (runtime.isNotEmpty)
                infoChips.add(_buildInfoChip(theme, runtime));
              if (downloads.isNotEmpty)
                infoChips.add(_buildInfoChip(theme, '$downloads downloads'));
              if (cachedFilesCount > 0) {
                final label =
                    'Cached $cachedFilesCount file${cachedFilesCount == 1 ? '' : 's'}';
                infoChips.add(_buildInfoChip(theme, label));
              }

              final infoRows = <Widget>[
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
                          heroTag: 'fav-meta:$cleanId',
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
      backgroundColor: theme.colorScheme.surfaceVariant,
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
