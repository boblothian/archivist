// lib/screens/archive_item_screen.dart
import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../archive_api.dart';
import '../media/media_player_ops.dart'; // in-app media players
import '../net.dart';
import '../services/discogs_service.dart';
import '../services/favourites_service.dart';
// 🔽 NEW: central queue support
import '../services/media_service.dart'; // MediaService, MediaType, Playable, MediaQueue
import '../utils.dart'; // downloadWithCache
import 'cbz_viewer_screen.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';

class ArchiveItemScreen extends StatefulWidget {
  final String title;
  final String identifier;
  final List<Map<String, String>> files;

  /// Thumb to reuse (from the collection/item card) — used ONLY for audio.
  final String? parentThumbUrl;

  final FavoriteItem? favoriteItem;

  const ArchiveItemScreen({
    super.key,
    required this.title,
    required this.identifier,
    required this.files,
    this.parentThumbUrl,
    this.favoriteItem,
  });

  @override
  State<ArchiveItemScreen> createState() => _ArchiveItemScreenState();
}

class _ArchiveItemScreenState extends State<ArchiveItemScreen> {
  final Map<String, double> _downloadProgress = {};

  // Collection support
  bool _checkedMetadata = false;
  bool _isCollection = false;
  String? _detailsUrl; // https://archive.org/details/<identifier>

  // 🔽 NEW: track if we primed MediaService queues
  bool _primedQueues = false;

  @override
  void initState() {
    super.initState();

    // Precompute details URL
    _detailsUrl = 'https://archive.org/details/${widget.identifier}';

    // Prime queues ASAP (does a lightweight metadata fetch and caches queues).
    _primeItemQueues();

    // If we have exactly one file, auto-open it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.files.length == 1) {
        final file = widget.files.first;
        final fileName = file['name']!;
        final fileUrl =
            'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(fileName)}';
        final thumbUrl = _getThumbnailUrl(fileName);
        _openFile(fileName, fileUrl, thumbUrl);
      }
    });

    // If no files were provided, check if this identifier is a collection.
    if (widget.files.isEmpty) {
      _detectCollection().then((_) {
        // After metadata check, also detect audio collections
        if (_isCollection == false && mounted) {
          _detectAudioCollection();
        }
      });
    }
    if (widget.files.isEmpty && !_isCollection) {
      _fetchFiles();
    }
  }

  // 🔽 NEW: prime queues in MediaService so auto-next has data
  Future<void> _primeItemQueues() async {
    try {
      final info = await MediaService.instance.fetchInfo(
        widget.identifier,
      ); // also primes
      ifMounted(this, () => _primedQueues = true);
    } catch (_) {
      // If fetch failed, we’ll build a local queue from files on demand.
      ifMounted(this, () => _primedQueues = false);
    }
  }

  Future<void> _detectAudioCollection() async {
    try {
      final meta = await ArchiveApi.getMetadata(widget.identifier);
      final md = (meta['metadata'] as Map?) ?? {};
      final mediatype = (md['mediatype'] ?? '').toString().toLowerCase();

      if (mediatype == 'audio' && (md['collection'] is List)) {
        ifMounted(this, () {
          setState(() {
            _isCollection = true;
            _checkedMetadata = true;
          });
        });
      }
    } catch (_) {
      ifMounted(this, () => setState(() => _checkedMetadata = true));
    }
  }

  Future<void> _detectCollection() async {
    try {
      final meta = await ArchiveApi.getMetadata(widget.identifier);
      final md = (meta['metadata'] as Map?) ?? {};
      final mediatype = (md['mediatype'] ?? '').toString().toLowerCase();

      // Only treat as collection if NOT audio/texts/movies with files
      if (mediatype == 'collection' ||
          (mediatype == 'audio' && widget.files.isEmpty) ||
          (mediatype == 'texts' && widget.files.isEmpty)) {
        ifMounted(this, () {
          setState(() {
            _isCollection = true;
            _checkedMetadata = true;
          });
        });
      } else {
        ifMounted(this, () => setState(() => _checkedMetadata = true));
      }
    } catch (_) {
      ifMounted(this, () => setState(() => _checkedMetadata = true));
    }
  }

  // Unified open function ------------------------------------------------------
  Future<void> _openFile(
    String fileName,
    String fileUrl,
    String thumbUrl,
  ) async {
    final ext = p.extension(fileName).toLowerCase();
    late final String kind;

    if (ext == '.pdf') {
      kind = 'pdf';
    } else if (ext == '.epub') {
      kind = 'epub';
      await _launchEpubExternal(fileName, fileUrl, thumbUrl);
      return;
    } else if (['.cbz', '.cbr'].contains(ext)) {
      kind = 'cbz';
    } else if (isImageFile(ext)) {
      kind = 'image';
    } else if (ext == '.txt' ||
        ext == '.md' ||
        ext == '.log' ||
        ext == '.csv') {
      // NOTE: per your request, leave text handling as-is (unchanged behavior).
      kind = 'text';
    } else if (isAudioFile(ext)) {
      kind = 'audio';

      // Record recents for audio before opening (keeps quick history entry)
      await RecentProgressService.instance.touch(
        id: widget.identifier,
        title: widget.title,
        // prefer using the parent thumb for audio
        thumb: widget.parentThumbUrl ?? thumbUrl,
        kind: kind,
        fileUrl: fileUrl,
        fileName: fileName,
      );

      // 🔽 NEW: Always try to play via QUEUE so auto-next works.
      await _playAudioViaQueue(fileName, fileUrl, thumbUrl);
      return;
    } else {
      ifMounted(this, () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unsupported file: $fileName')));
      });
      return;
    }

    // --- Non-audio types ------------------------------------------------------
    await RecentProgressService.instance.touch(
      id: widget.identifier,
      title: widget.title,
      thumb: thumbUrl,
      kind: kind,
      fileUrl: fileUrl,
      fileName: fileName,
    );

    try {
      final cachedFile = await downloadWithCache(
        url: fileUrl,
        filenameHint: fileName,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            final p = received / total;
            ifMounted(
              this,
              () => setState(() => _downloadProgress[fileName] = p),
            );
          }
        },
      );

      Widget? viewer;

      if (ext == '.pdf') {
        viewer = PdfViewerScreen(
          file: cachedFile,
          url: fileUrl, // optional, but helpful for progress metadata
          filenameHint: fileName, // Resume should be per-file
          identifier: widget.identifier,
          title: widget.title,
          thumbUrl: thumbUrl,
        );
      } else if (['.cbz', '.cbr'].contains(ext)) {
        viewer = CbzViewerScreen(
          cbzFile: cachedFile,
          title: widget.title,
          identifier: widget.identifier,
        );
      } else if (isImageFile(ext)) {
        viewer = ImageViewerScreen(imageUrls: [cachedFile.path]);
      }

      if (viewer != null) {
        ifMounted(this, () {
          setState(() => _downloadProgress.remove(fileName));
          Navigator.push(context, MaterialPageRoute(builder: (_) => viewer!));
        });
      }
    } catch (e) {
      ifMounted(this, () {
        setState(() => _downloadProgress.remove(fileName));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open: $e')));
      });
    }
  }

  Future<void> _playAudioViaQueue(
    String fileName,
    String fileUrl,
    String thumbUrl,
  ) async {
    final itemThumb = widget.parentThumbUrl ?? thumbUrl;

    // 1) Prefer a primed/cached queue from MediaService
    MediaQueue? q =
        MediaService.instance.getQueue(
          widget.identifier,
          MediaType.audio,
          startUrl: fileUrl,
        ) ??
        MediaService.instance.getQueueByUrl(fileUrl, MediaType.audio);

    // 2) Fallback: build a queue from on-screen audio files if needed
    if (q == null) {
      // Preserve the order of widget.files initially
      var files = widget.files;

      // 🔽 NEW: if we have a saved Discogs order, apply it
      try {
        files = await DiscogsService.instance.applySavedOrderToFiles(
          identifier: widget.identifier,
          files: files,
        );
      } catch (_) {
        // ignore; just keep original order on failure
      }

      final entries = <({String name, String url})>[];

      for (final f in files) {
        final name = f['name'];
        if (name == null) continue;
        final ext = p.extension(name).toLowerCase();
        if (!isAudioFile(ext)) continue;

        final url =
            'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(name)}';

        entries.add((name: name, url: url));
      }

      final items =
          entries
              .map(
                (e) => Playable(url: e.url, title: _prettifyFilename(e.name)),
              )
              .toList();

      final start = items.indexWhere((p) => p.url == fileUrl);

      q = MediaQueue(
        items: items,
        type: MediaType.audio,
        startIndex: start >= 0 ? start : 0,
      );
    }

    // 🔽 Ensure the queue will start at the file the user tapped
    int startIndex = q.startIndex;

    // Re-check using the exact URL, just in case
    try {
      final idx = q.items.indexWhere((p) => (p.url) == fileUrl);
      if (idx >= 0) {
        startIndex = idx;
      }
    } catch (_) {
      // ignore; keep previous startIndex
    }

    // Rebuild q because MediaQueue fields are final
    q = MediaQueue(items: q.items, type: q.type, startIndex: startIndex);
  
    // 3) Launch the queue-enabled audio player
    final MediaQueue finalQueue = q;

    await MediaPlayerOps.playAudioQueue(
      context,
      queue: finalQueue,
      identifier: widget.identifier,
      title: widget.title,
      startPositionMs: 0,
      itemThumb: itemThumb,
    );
  }

  Future<void> _fetchFiles() async {
    try {
      final files = await ArchiveApi.fetchFilesForIdentifier(widget.identifier);
      if (mounted) {
        setState(() {
          // Rebuild with files
          widget.files.addAll(files.map((f) => {'name': f['name']!}).toList());
        });
      }
      // If queues weren’t primed by network, ensure we have *some* queue soon after files arrive.
      if (!_primedQueues && mounted) {
        // No-op here; we build fallback queues on demand in _playAudioViaQueue.
        // You could optionally trigger _primeItemQueues() again if desired.
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load files: $e')));
      }
    }
  }

  // Launch EPUBs with external reader
  Future<void> _launchEpubExternal(
    String fileName,
    String fileUrl,
    String thumbUrl,
  ) async {
    try {
      final cachedFile = await downloadWithCache(
        url: fileUrl,
        filenameHint: fileName,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            final p = received / total;
            ifMounted(
              this,
              () => setState(() => _downloadProgress[fileName] = p),
            );
          }
        },
      );

      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission required for EPUB'),
            ),
          );
          return;
        }
      }

      final result = await OpenFilex.open(
        cachedFile.path,
        type: 'application/epub+zip',
      );
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No EPUB reader: ${result.message}')),
        );
      }

      ifMounted(this, () => setState(() => _downloadProgress.remove(fileName)));
    } catch (e) {
      ifMounted(this, () {
        setState(() => _downloadProgress.remove(fileName));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('EPUB error: $e')));
      });
    }
  }

  // Thumbnails ---------------------------------------------------------------
  String _getThumbnailUrl(String fileName) {
    final ext = p.extension(fileName).toLowerCase();

    // For AUDIO use the collection/item thumbnail if provided.
    if (isAudioFile(ext) && (widget.parentThumbUrl?.isNotEmpty ?? false)) {
      return widget.parentThumbUrl!;
    }

    if (ext == '.pdf') {
      return buildJp2ThumbnailUrl(fileName, widget.identifier);
    }
    if (isImageFile(ext)) {
      return 'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(fileName)}';
    }
    // Fallback: services/img of the item
    return 'https://archive.org/services/img/${widget.identifier}';
  }

  String buildJp2ThumbnailUrl(String pdfName, String identifier) {
    final base = pdfName.replaceAll('.pdf', '');
    final encoded = Uri.encodeComponent(base);
    return 'https://archive.org/download/$identifier/${encoded}_jp2.zip/${encoded}_jp2/${encoded}_0000.jp2&ext=jpg';
  }

  // Utilities ----------------------------------------------------------------
  String _prettifyFilename(String name) {
    final ext = p.extension(name);
    name = name.replaceAll(ext, '');
    final match = RegExp(r'^(\d+)[_\s-]+(.*)').firstMatch(name);
    String number = '';
    String title = name;

    if (match != null) {
      number = match.group(1)!;
      title = match.group(2)!;
    }

    title = title.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    title = title
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');

    return number.isNotEmpty ? '$number. $title$ext' : '$title$ext';
  }

  // File type helpers --------------------------------------------------------
  bool isImageFile(String ext) =>
      ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext);
  bool isTextFile(String ext) => ['.txt', '.md', '.log', '.csv'].contains(ext);
  bool isAudioFile(String ext) =>
      ['.mp3', '.ogg', '.flac', '.m4a', '.wav', '.opus', '.aac'].contains(ext);

  // Build --------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final allFiles = widget.files;

    // Categorize
    final pdfFiles = <Map<String, String>>[];
    final imageFiles = <Map<String, String>>[];
    final textFiles = <Map<String, String>>[];
    final audioFiles = <Map<String, String>>[];

    for (final file in allFiles) {
      final name = file['name'] ?? '';
      final ext = p.extension(name).toLowerCase();

      if (ext == '.pdf' && !name.toLowerCase().endsWith('_text.pdf')) {
        pdfFiles.add(file);
      } else if (isImageFile(ext)) {
        imageFiles.add(file);
      } else if (isTextFile(ext)) {
        textFiles.add(file);
      } else if (isAudioFile(ext)) {
        audioFiles.add(file);
      }
    }

    final displayFiles = [
      ...imageFiles,
      ...pdfFiles,
      ...textFiles,
      ...audioFiles,
    ];

    // --- Collection-friendly empty state
    if (displayFiles.isEmpty) {
      // If we haven't finished checking metadata yet, show a spinner.
      if (!_checkedMetadata) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }

      // If it's a collection, show a friendly collection message + open-link.
      if (_isCollection) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_open, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'This is a collection on Archive.org.',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Collections don’t have files themselves. Open it on Archive.org to browse items inside.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Browse on Archive.org'),
                    onPressed: () async {
                      final url = _detailsUrl!;
                      final uri = Uri.parse(url);
                      final ok = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not open link')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Not a collection; just no supported files.
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('No supported files found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.52,
        ),
        itemCount: displayFiles.length,
        itemBuilder: (context, index) {
          final file = displayFiles[index];
          final fileName = file['name']!;
          final ext = p.extension(fileName).toLowerCase();
          final fileUrl =
              'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(fileName)}';
          final thumbUrl = _getThumbnailUrl(fileName);

          final isPdf = ext == '.pdf';
          final isImage = isImageFile(ext);
          final isText = isTextFile(ext);
          final isAudio = isAudioFile(ext);

          return Stack(
            children: [
              InkWell(
                onTap: () => _openFile(fileName, fileUrl, thumbUrl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 🔽 FIXED-SIZE THUMBNAIL
                    AspectRatio(
                      aspectRatio: 2 / 3, // 3:4 cover art
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: () {
                                  if (isPdf || isImage || isAudio) {
                                    return CachedNetworkImage(
                                      httpHeaders: Net.headers,
                                      imageUrl: thumbUrl,
                                      fit: BoxFit.cover,
                                      placeholder:
                                          (_, __) => const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1,
                                            ),
                                          ),
                                      errorWidget:
                                          (_, __, ___) => Container(
                                            color: Colors.grey[300],
                                            alignment: Alignment.center,
                                            child: Icon(
                                              isAudio
                                                  ? Icons.audiotrack
                                                  : Icons.broken_image,
                                              size: 48,
                                              color: Colors.black54,
                                            ),
                                          ),
                                    );
                                  } else if (isText) {
                                    return Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.description,
                                        size: 48,
                                        color: Colors.black54,
                                      ),
                                    );
                                  }
                                  return const SizedBox();
                                }(),
                              ),
                              if (_downloadProgress[fileName] != null) ...[
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.4),
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: LinearProgressIndicator(
                                    value: _downloadProgress[fileName],
                                    minHeight: 8,
                                    backgroundColor: Colors.black.withOpacity(
                                      0.3,
                                    ),
                                    valueColor: const AlwaysStoppedAnimation(
                                      Colors.lightBlueAccent,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Center(
                                    child: Text(
                                      '${(_downloadProgress[fileName]! * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // 🔽 FIXED HEIGHT FOR UP TO ~2 LINES
                    SizedBox(
                      height: 32, // tweak if font size changes
                      child: Text(
                        _prettifyFilename(fileName),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),

                    if (isAudio)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.audiotrack,
                          size: 14,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Helper
void ifMounted(State state, VoidCallback callback) {
  if (state.mounted) callback();
}
