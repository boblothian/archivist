// archive_item_screen.dart
import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/text_viewer_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cbz_viewer_screen.dart';
import 'epub_viewer_screen.dart';
import 'net.dart';
import 'pdf_viewer_screen.dart';
import 'services/jellyfin_service.dart';
import 'utils.dart'; // ← Required for downloadWithCache

class ArchiveItemScreen extends StatefulWidget {
  final String title;
  final String identifier;
  final List<Map<String, String>> files;

  const ArchiveItemScreen({
    super.key,
    required this.title,
    required this.identifier,
    required this.files,
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

    // AUTO-OPEN IF SINGLE FILE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.files.length == 1) {
        final fileName = widget.files.first['name']!;
        final fileUrl =
            'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(fileName)}';
        final thumbUrl = buildJp2ThumbnailUrl(fileName, widget.identifier);
        _openFile(fileName, fileUrl, thumbUrl);
      }
    });
  }

  // Unified open function: cache + progress + auto-open
  Future<void> _openFile(
    String fileName,
    String fileUrl,
    String thumbUrl, // ← NEW
  ) async {
    final ext = p.extension(fileName).toLowerCase();
    late final Widget viewer;
    late final String kind;

    if (ext == '.pdf') {
      viewer = PdfViewerScreen(
        url: fileUrl,
        filenameHint: fileName,
        identifier: widget.identifier,
        title: widget.title,
        thumbUrl: thumbUrl, // ← PASS IT!
      );
      kind = 'pdf';
    } else if (ext == '.epub') {
      viewer = EpubViewerScreen(
        url: fileUrl,
        filenameHint: fileName,
        identifier: widget.identifier,
        title: widget.title,
      );
      kind = 'epub';
    } else if (['.cbz', '.cbr'].contains(ext)) {
      viewer = CbzViewerScreen(
        url: fileUrl,
        filenameHint: fileName,
        title: widget.title,
        identifier: widget.identifier,
      );
      kind = 'cbz';
    } else if (ext == '.txt') {
      viewer = TextViewerScreen(
        url: fileUrl,
        filenameHint: fileName,
        identifier: widget.identifier,
        title: widget.title,
      );
      kind = 'text';
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unsupported: $fileName')));
      return;
    }

    // SAVE THUMBNAIL FROM JP2!
    await RecentProgressService.instance.touch(
      id: widget.identifier,
      title: widget.title,
      thumb: thumbUrl, // ← NOW SAVED!
      kind: kind,
      fileUrl: fileUrl,
      fileName: fileName,
    );

    try {
      final cachedFile = await downloadWithCache(
        url: fileUrl,
        filenameHint: fileName,
        onProgress:
            (p) => ifMounted(
              this,
              () => setState(() => _downloadProgress[fileName] = p),
            ),
      );

      Widget finalViewer;
      if (ext == '.pdf') {
        finalViewer = PdfViewerScreen(
          file: cachedFile,
          identifier: widget.identifier,
          title: widget.title,
        );
      } else {
        finalViewer = viewer; // EPUB/CBZ/TXT use URL
      }

      ifMounted(this, () {
        setState(() => _downloadProgress.remove(fileName));
        Navigator.push(context, MaterialPageRoute(builder: (_) => finalViewer));
      });
    } catch (e) {
      ifMounted(this, () {
        setState(() => _downloadProgress.remove(fileName));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      });
    }
  }

  void _saveToJellyfin(String fileUrl, String title) async {
    final svc = JellyfinService.instance;
    final cfg = await svc.loadConfig() ?? await svc.showConfigDialog(context);
    if (cfg == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Uploading to Jellyfin…')));

    try {
      await svc.addMovieFromUrl(
        url: Uri.parse(fileUrl),
        title: title,
        httpHeaders: Net.headers,
        onProgress: (sent, total) {
          if (total != null && total > 0) {
            final pct = ((sent / total) * 100).floor();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Uploading… $pct%')));
          }
        },
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to Jellyfin! Library refresh triggered.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

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
      final thumbUrl = buildJp2ThumbnailUrl(fileName, widget.identifier);
      _openFile(fileName, fileUrl, thumbUrl); // ← NOW 3 args
    }

    await prefs.setStringList('reading_list', _favoriteFiles.toList());
    setState(() {});
  }

  String buildJp2ThumbnailUrl(String pdfName, String identifier) {
    final base = pdfName.replaceAll('.pdf', '');
    final encoded = Uri.encodeComponent(base);
    return 'https://archive.org/download/$identifier/$encoded'
        '_jp2.zip/$encoded'
        '_jp2/$encoded'
        '_0000.jp2&ext=jpg';
  }

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
    name = name.replaceAll('.pdf', '');
    final match = RegExp(r'^(\d+)[_\s-]+(.*)').firstMatch(name);
    String number = '';
    String title = name;

    if (match != null) {
      number = match.group(1)!;
      title = match.group(2)!;
    }

    title = title.replaceAll(RegExp(r'[_-]+'), ' ');
    title = title
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');

    return number.isNotEmpty ? '$number. $title' : title;
  }

  bool _isVideoFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  @override
  Widget build(BuildContext context) {
    final allFiles = widget.files;

    final pdfFiles =
        allFiles.where((file) {
            final name = file['name']?.toLowerCase() ?? '';
            return name.endsWith('.pdf') && !name.endsWith('_text.pdf');
          }).toList()
          ..sort((a, b) => _naturalCompare(a['name'] ?? '', b['name'] ?? ''));

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
        itemCount: pdfFiles.length,
        itemBuilder: (context, index) {
          final file = pdfFiles[index];
          final fileName = file['name']!;
          final fileUrl =
              'https://archive.org/download/${widget.identifier}/${Uri.encodeComponent(fileName)}';
          final thumbnailUrl = buildJp2ThumbnailUrl(
            fileName,
            widget.identifier,
          );
          final isFavorited = _favoriteFiles.contains(fileName);

          return Stack(
            children: [
              InkWell(
                onTap: () => _openFile(fileName, fileUrl, thumbnailUrl),
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
                                child: CachedNetworkImage(
                                  httpHeaders: Net.headers,
                                  imageUrl: thumbnailUrl,
                                  fit: BoxFit.contain,
                                  placeholder:
                                      (context, url) => const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1,
                                        ),
                                      ),
                                  errorWidget:
                                      (context, url, error) => const Center(
                                        child: Text('No preview'),
                                      ),
                                ),
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
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
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
                                        shadows: [
                                          Shadow(
                                            blurRadius: 2,
                                            color: Colors.black,
                                          ),
                                        ],
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
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isVideoFile(fileName))
                      IconButton(
                        icon: const Icon(
                          Icons.cloud_upload,
                          color: Colors.lightBlueAccent,
                        ),
                        tooltip: 'Save to Jellyfin',
                        onPressed: () => _saveToJellyfin(fileUrl, fileName),
                      ),
                    IconButton(
                      icon: Icon(
                        isFavorited ? Icons.favorite : Icons.favorite_border,
                        color: isFavorited ? Colors.red : Colors.white,
                      ),
                      onPressed: () => _toggleFavorite(fileName, fileUrl),
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
