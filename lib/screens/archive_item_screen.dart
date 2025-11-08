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
import '../media/media_player_ops.dart'; // ← use in-app audio player
import '../net.dart';
import '../utils.dart'; // For downloadWithCache
import 'cbz_viewer_screen.dart';
import 'image_viewer_screen.dart'; // for image galleries
import 'pdf_viewer_screen.dart';

class ArchiveItemScreen extends StatefulWidget {
  final String title;
  final String identifier;
  final List<Map<String, String>> files;

  /// Thumb to reuse (from the collection/item card) — used ONLY for audio.
  final String? parentThumbUrl;

  const ArchiveItemScreen({
    super.key,
    required this.title,
    required this.identifier,
    required this.files,
    this.parentThumbUrl,
  });

  @override
  State<ArchiveItemScreen> createState() => _ArchiveItemScreenState();
}

class _ArchiveItemScreenState extends State<ArchiveItemScreen> {
  final Map<String, double> _downloadProgress = {};

  // NEW: collection support
  bool _checkedMetadata = false;
  bool _isCollection = false;
  String? _detailsUrl; // https://archive.org/details/<identifier>

  @override
  void initState() {
    super.initState();

    // Precompute details URL
    _detailsUrl = 'https://archive.org/details/${widget.identifier}';

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
      _detectCollection();
    }
  }

  Future<void> _detectCollection() async {
    try {
      final meta = await ArchiveApi.getMetadata(widget.identifier);
      final m = (meta['metadata'] as Map?) ?? const {};
      final type = (m['mediatype'] ?? '').toString().toLowerCase();
      ifMounted(this, () {
        _isCollection = type == 'collection';
        _checkedMetadata = true;
        setState(() {});
      });
    } catch (_) {
      ifMounted(this, () {
        _checkedMetadata = true; // even on error, stop a spinner loop
        setState(() {});
      });
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

      // Always use in-app audio player
      await MediaPlayerOps.playAudio(
        context,
        url: fileUrl,
        identifier: widget.identifier,
        title: widget.title,
        // You can also pass startPositionMs if you track it elsewhere
        thumb: widget.parentThumbUrl ?? thumbUrl,
        fileName: fileName,
      );
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
  int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final aMatches = regex.allMatches(a);
    final bMatches = regex.allMatches(b);
    final aParts = aMatches.map((m) => m.group(0)!).toList();
    final bParts = bMatches.map((m) => m.group(0)!).toList();
    final len = aParts.length < bParts.length ? aParts.length : bParts.length;

    for (int i = 0; i < len; i++) {
      final aPart = aParts[i];
      final bPart = bParts[i];
      final aNum = int.tryParse(aPart);
      final bNum = int.tryParse(bPart);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aPart.compareTo(bPart);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

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
  bool isAudioFile(String ext) => ['.mp3'].contains(ext);

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

    // Sort each
    pdfFiles.sort((a, b) => _naturalCompare(a['name'] ?? '', b['name'] ?? ''));
    imageFiles.sort(
      (a, b) => _naturalCompare(a['name'] ?? '', b['name'] ?? ''),
    );
    textFiles.sort((a, b) => _naturalCompare(a['name'] ?? '', b['name'] ?? ''));
    audioFiles.sort(
      (a, b) => _naturalCompare(a['name'] ?? '', b['name'] ?? ''),
    );

    final displayFiles = [
      ...imageFiles,
      ...pdfFiles,
      ...textFiles,
      ...audioFiles,
    ];

    // --- NEW: Collection-friendly empty state
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
          childAspectRatio: 0.7,
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
                  children: [
                    Expanded(
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
                                  // treat audio like image for preview if we have a thumb
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
                              if (_downloadProgress[fileName] != null)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.4),
                                  ),
                                ),
                              if (_downloadProgress[fileName] != null)
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
                              if (_downloadProgress[fileName] != null)
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
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _prettifyFilename(fileName),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
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
