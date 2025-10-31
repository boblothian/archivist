// archive_item_screen.dart
import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart'; // Correct package
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cbz_viewer_screen.dart';
import 'net.dart';
import 'pdf_viewer_screen.dart';
import 'utils.dart'; // For downloadWithCache

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
    String thumbUrl,
  ) async {
    final ext = p.extension(fileName).toLowerCase();
    late final String kind;

    if (ext == '.pdf') {
      kind = 'pdf';
    } else if (ext == '.epub') {
      kind = 'epub';
      await _launchEpubExternal(fileName, fileUrl, thumbUrl);
      return; // No Navigator.push
    } else if (['.cbz', '.cbr'].contains(ext)) {
      kind = 'cbz';
    } else if (ext == '.txt') {
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

      // NOW: Use cachedFile for ALL viewers
      Widget finalViewer;
      if (ext == '.pdf') {
        finalViewer = PdfViewerScreen(
          file: cachedFile,
          identifier: widget.identifier,
          title: widget.title,
        );
      } else if (['.cbz', '.cbr'].contains(ext)) {
        finalViewer = CbzViewerScreen(
          cbzFile: cachedFile,
          title: widget.title,
          identifier: widget.identifier,
        );
      } else {
        finalViewer = Container();
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

  // Launch EPUB in external reader
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

      // Request storage permission (Android)
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission required to open EPUB'),
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
          SnackBar(
            content: Text('No app found to open EPUB: ${result.message}'),
          ),
        );
      }

      ifMounted(this, () => setState(() => _downloadProgress.remove(fileName)));
    } catch (e) {
      ifMounted(this, () {
        setState(() => _downloadProgress.remove(fileName));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open EPUB: $e')));
      });
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
      _openFile(fileName, fileUrl, thumbUrl);
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

// Helper to prevent setState after dispose
void ifMounted(State state, VoidCallback callback) {
  if (state.mounted) callback();
}
