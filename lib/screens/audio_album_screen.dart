// lib/screens/audio_album_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../media/media_player_ops.dart';
import '../services/discogs_service.dart';
import '../services/media_service.dart';
import '../services/recent_progress_service.dart';
import '../utils/archive_helpers.dart';

class AudioAlbumScreen extends StatefulWidget {
  final String identifier;
  final String title;
  final List<Map<String, String>> files; // expects {"name": ...}
  final String? thumbUrl;

  const AudioAlbumScreen({
    super.key,
    required this.identifier,
    required this.title,
    required this.files,
    this.thumbUrl,
  });

  @override
  State<AudioAlbumScreen> createState() => _AudioAlbumScreenState();
}

class _AudioAlbumScreenState extends State<AudioAlbumScreen> {
  late List<Map<String, String>> _tracks;

  @override
  void initState() {
    super.initState();
    _tracks = List<Map<String, String>>.from(widget.files);
    _applyDiscogsOrder();
  }

  Future<void> _applyDiscogsOrder() async {
    try {
      await DiscogsService.instance.sortAudioFilesForItem(
        identifier: widget.identifier,
        files: _tracks,
      );
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      // ignore; keep natural order
    }
  }

  bool _isAudioName(String name) {
    final ext = p.extension(name).toLowerCase();
    return [
      '.mp3',
      '.ogg',
      '.flac',
      '.m4a',
      '.wav',
      '.opus',
      '.aac',
    ].contains(ext);
  }

  String _prettifyFilename(String name) {
    final ext = p.extension(name);
    var base = name.replaceAll(ext, '');
    final match = RegExp(r'^(\d+)[_\s-]+(.*)').firstMatch(base);
    String number = '';
    String title = base;

    if (match != null) {
      number = match.group(1)!;
      title = match.group(2)!;
    }

    title = title
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim()
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');

    return number.isNotEmpty ? '$number. $title' : title;
  }

  Future<void> _playFromIndex(int index) async {
    final entries = <({String name, String url})>[];

    for (final f in _tracks) {
      final name = f['name'];
      if (name == null) continue;
      if (!_isAudioName(name)) continue;

      final url =
          'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(name)}';
      entries.add((name: name, url: url));
    }

    if (entries.isEmpty) return;

    final items =
        entries
            .map((e) => Playable(url: e.url, title: _prettifyFilename(e.name)))
            .toList();

    if (index < 0 || index >= items.length) index = 0;

    final queue = MediaQueue(
      items: items,
      type: MediaType.audio,
      startIndex: index,
    );

    final thumb = widget.thumbUrl ?? archiveThumbUrl(widget.identifier);

    await RecentProgressService.instance.touch(
      id: widget.identifier,
      title: widget.title,
      thumb: thumb,
      kind: 'audio',
    );

    if (!mounted) return;

    await MediaPlayerOps.playAudioQueue(
      context,
      queue: queue,
      identifier: widget.identifier,
      title: widget.title,
      itemThumb: thumb,
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumb =
        widget.thumbUrl?.isNotEmpty == true
            ? widget.thumbUrl!
            : archiveThumbUrl(widget.identifier);

    // Responsive-ish cover size
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final coverSize = shortestSide < 600 ? 120.0 : 160.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          // HEADER
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity, // give Row tight width
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Constrained cover art
                  SizedBox(
                    width: coverSize,
                    height: coverSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Text + buttons
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_tracks.length} track${_tracks.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play all'),
                              onPressed:
                                  _tracks.isEmpty
                                      ? null
                                      : () => _playFromIndex(0),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.shuffle),
                              label: const Text('Shuffle'),
                              onPressed:
                                  _tracks.isEmpty
                                      ? null
                                      : () {
                                        final idx =
                                            _tracks.isEmpty
                                                ? 0
                                                : (DateTime.now()
                                                        .millisecondsSinceEpoch %
                                                    _tracks.length);
                                        _playFromIndex(idx);
                                      },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // TRACK LIST
          Expanded(
            child: ListView.separated(
              itemCount: _tracks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final t = _tracks[index];
                final name = t['name'] ?? '';
                final title = _prettifyFilename(name);

                return ListTile(
                  leading: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () => _playFromIndex(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
