import 'dart:io';

// For launching Android media apps directly
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cbz_viewer_screen.dart';
import 'image_viewer_screen.dart'; // for image galleries
import 'net.dart';
import 'pdf_viewer_screen.dart';
import 'utils.dart'; // For downloadWithCache

class ArchiveItemScreen extends StatefulWidget {
  final String title;
  final String identifier;
  final List<Map<String, String>> files;

  /// NEW: Thumb to reuse (from the collection/item card) — used ONLY for audio.
  final String? parentThumbUrl;

  const ArchiveItemScreen({
    super.key,
    required this.title,
    required this.identifier,
    required this.files,
    this.parentThumbUrl, // ← NEW (optional)
  });

  @override
  State<ArchiveItemScreen> createState() => _ArchiveItemScreenState();
}

class _ArchiveItemScreenState extends State<ArchiveItemScreen> {
  Set<String> _favoriteFiles = {};
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();

    // Auto-open if single file
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
  }

  // --- Android: open audio URL directly in installed media player ------------
  Future<bool> _openAudioInInstalledApp(String url) async {
    try {
      if (Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'action_view', // Intent.ACTION_VIEW
          data: url, // http(s) stream URL
          type: 'audio/*', // force media player, not browser
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return true;
      }
      return false; // iOS/macOS: fall back below
    } catch (_) {
      return false;
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
      kind = 'text';
    } else if (isAudioFile(ext)) {
      kind = 'audio';

      // Record recents for audio before opening
      await RecentProgressService.instance.touch(
        id: widget.identifier,
        title: widget.title,
        // NEW: prefer using the parent thumb for audio
        thumb: widget.parentThumbUrl ?? thumbUrl,
        kind: kind,
        fileUrl: fileUrl,
        fileName: fileName,
      );

      // 1) Try to stream directly in the device’s media player (Android)
      final opened = await _openAudioInInstalledApp(fileUrl);
      if (opened) {
        ifMounted(this, () => _downloadProgress.remove(fileName));
        return;
      }

      // 2) Fallback: download then open locally with OpenFilex
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

        final result = await OpenFilex.open(cachedFile.path, type: 'audio/*');
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No app to play audio: ${result.message}')),
          );
        }
      } catch (e) {
        ifMounted(this, () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Audio open error: $e')));
        });
      } finally {
        ifMounted(
          this,
          () => setState(() => _downloadProgress.remove(fileName)),
        );
      }
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
          identifier: widget.identifier,
          title: widget.title,
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

  // Favourites ---------------------------------------------------------------
  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteFiles = prefs.getStringList('reading_list')?.toSet() ?? {};
    setState(() {});
  }

  Future<void> _toggleFavorite(String fileName, String fileUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/$fileName');

    if (_favoriteFiles.contains(fileName)) {
      _favoriteFiles.remove(fileName);
      if (await file.exists()) await file.delete();
    } else {
      _favoriteFiles.add(fileName);
      final thumbUrl = _getThumbnailUrl(fileName);
      _openFile(fileName, fileUrl, thumbUrl);
    }

    await prefs.setStringList('reading_list', _favoriteFiles.toList());
    setState(() {});
  }

  // Thumbnails ---------------------------------------------------------------
  String _getThumbnailUrl(String fileName) {
    final ext = p.extension(fileName).toLowerCase();

    // NEW: For AUDIO use the collection/item thumbnail if provided.
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
      ...pdfFiles,
      ...imageFiles,
      ...textFiles,
      ...audioFiles,
    ];

    if (displayFiles.isEmpty) {
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
          final isFavorited = _favoriteFiles.contains(fileName);

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
                                  // NEW: treat audio like image for preview if we have a thumb
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
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: Icon(
                    isFavorited ? Icons.favorite : Icons.favorite_border,
                    color: isFavorited ? Colors.red : Colors.white,
                  ),
                  onPressed: () => _toggleFavorite(fileName, fileUrl),
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
