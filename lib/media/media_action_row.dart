// lib/media/media_action_row.dart
import 'package:flutter/material.dart';

import '../services/downloads_service.dart'; // your DownloadsService
import '../services/media_service.dart'; // ArchiveMediaInfo + MediaService + MediaType
import 'media_player_ops.dart';

class MediaActionRow extends StatefulWidget {
  final String identifier;
  final String title;

  /// If you already have the media info, you can pass it to avoid refetching.
  final ArchiveMediaInfo? preloaded;

  const MediaActionRow({
    super.key,
    required this.identifier,
    required this.title,
    this.preloaded,
  });

  @override
  State<MediaActionRow> createState() => _MediaActionRowState();
}

class _MediaActionRowState extends State<MediaActionRow> {
  final _svc = MediaService.instance;

  ArchiveMediaInfo? _info;
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // If parent provided info, use it; otherwise fetch (which also primes queues)
      final info = widget.preloaded ?? await _svc.fetchInfo(widget.identifier);
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'Failed to load media info';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_info == null) {
      return Text(_status ?? 'No media');
    }

    final info = _info!;
    final canDownload = DownloadsService.instance.isLicenseDownloadable(
      license: info.license,
      rights: info.rights,
    );

    final bestVideo = MediaPlayerOps.pickBestVideoUrl(info.videoUrls);
    final bestAudio = MediaPlayerOps.pickBestAudioUrl(info.audioUrls);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (bestVideo != null)
          ElevatedButton.icon(
            icon: const Icon(Icons.play_circle),
            label: const Text('Play Video'),
            onPressed: () async {
              // Prefer a cached queue (primed by fetchInfo); else build from info.
              final q =
                  _svc.getQueue(
                    info.identifier,
                    MediaType.video,
                    startUrl: bestVideo,
                  ) ??
                  _svc.buildQueueForInfo(
                    info,
                    type: MediaType.video,
                    startUrl: bestVideo,
                  );

              await MediaPlayerOps.playVideoQueue(
                context,
                queue: q,
                identifier: info.identifier,
                title: widget.title,
              );
            },
          ),
        if (bestAudio != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.audiotrack),
            label: const Text('Play Audio'),
            onPressed: () async {
              // Prefer a cached queue (primed by fetchInfo); else build from info.
              final q =
                  _svc.getQueue(
                    info.identifier,
                    MediaType.audio,
                    startUrl: bestAudio,
                  ) ??
                  _svc.buildQueueForInfo(
                    info,
                    type: MediaType.audio,
                    startUrl: bestAudio,
                  );

              // Use the item poster as artwork in the audio UI
              final itemThumb =
                  'https://archive.org/services/img/${info.identifier}';

              await MediaPlayerOps.playAudioQueue(
                context,
                queue: q,
                identifier: info.identifier,
                title: widget.title,
                itemThumb: itemThumb,
              );
            },
          ),
        if (canDownload && (bestVideo != null || bestAudio != null))
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download (PD/CC)'),
            onPressed: () async {
              final url = bestVideo ?? bestAudio!;
              setState(() => _status = 'Downloading…');
              try {
                final path = await DownloadsService.instance.downloadMedia(
                  identifier: info.identifier,
                  url: url,
                  suggestedFileName: info.displayNames[url],
                  onProgress: (r, t) {
                    setState(
                      () =>
                          _status =
                              t == 0
                                  ? 'Downloading…'
                                  : 'Downloading… ${(r / t * 100).toStringAsFixed(0)}%',
                    );
                  },
                );
                setState(() => _status = 'Saved: $path');
              } catch (e) {
                setState(() => _status = 'Download failed');
              }
            },
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
