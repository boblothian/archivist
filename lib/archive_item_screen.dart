import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';
import 'pdf_viewer_screen.dart';
import 'services/jellyfin_service.dart';

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
  final Set<String> _loadingFiles = {};
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
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
    final filePath = '${appDir.path}/$fileName';
    final file = File(filePath);

    if (_favoriteFiles.contains(fileName)) {
      _favoriteFiles.remove(fileName);
      if (await file.exists()) await file.delete();
    } else {
      if (!await file.exists()) {
        final uri = Uri.parse(fileUrl);
        final request = http.Request('GET', uri);
        final response = await request.send();

        final total = response.contentLength ?? 0;
        int received = 0;
        final fileSink = file.openWrite();

        await response.stream.listen(
          (chunk) {
            fileSink.add(chunk);
            received += chunk.length;
            setState(() {
              _downloadProgress[fileName] =
                  (total > 0 ? received / total : null)!;
            });
          },
          onDone: () async {
            await fileSink.close();
            setState(() {
              _downloadProgress.remove(fileName);
            });

            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PdfViewerScreen(file: file)),
            );
          },
          onError: (e) async {
            await fileSink.close();
            setState(() {
              _downloadProgress.remove(fileName);
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
          },
          cancelOnError: true,
        );
      }
      _favoriteFiles.add(fileName);
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

  // 🔹 Detect if a file is a video
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
                onTap: () async {
                  final tempDir = await getTemporaryDirectory();
                  final filePath = '${tempDir.path}/$fileName';
                  final file = File(filePath);

                  if (await file.exists()) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(file: file),
                      ),
                    );
                    return;
                  }

                  setState(() {
                    _loadingFiles.add(fileName);
                    _downloadProgress[fileName] = 0.0;
                  });

                  try {
                    final uri = Uri.parse(fileUrl);
                    final request = http.Request('GET', uri);
                    final response = await request.send();

                    final total = response.contentLength ?? 0;
                    int received = 0;
                    final fileSink = file.openWrite();

                    await response.stream.listen(
                      (chunk) {
                        fileSink.add(chunk);
                        received += chunk.length;
                        setState(() {
                          _downloadProgress[fileName] =
                              (total > 0 ? received / total : null)!;
                        });
                      },
                      onDone: () async {
                        await fileSink.close();
                        setState(() {
                          _loadingFiles.remove(fileName);
                          _downloadProgress.remove(fileName);
                        });

                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfViewerScreen(file: file),
                          ),
                        );
                      },
                      onError: (e) async {
                        await fileSink.close();
                        setState(() {
                          _loadingFiles.remove(fileName);
                          _downloadProgress.remove(fileName);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Download failed: $e')),
                        );
                      },
                      cancelOnError: true,
                    );
                  } catch (e) {
                    setState(() {
                      _loadingFiles.remove(fileName);
                      _downloadProgress.remove(fileName);
                    });
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
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
