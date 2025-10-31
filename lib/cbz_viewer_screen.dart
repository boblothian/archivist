// lib/screens/cbz_viewer_screen.dart
import 'dart:convert'; // ← NEW: for manifest JSON
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart'; // ← NEW: for page resume

import 'utils.dart';

class CbzViewerScreen extends StatefulWidget {
  final File? cbzFile;
  final String title;
  final String? url;
  final String? filenameHint;
  final String? identifier; // ← NEW: for progress

  const CbzViewerScreen({
    super.key,
    this.cbzFile,
    required this.title,
    this.url,
    this.filenameHint,
    this.identifier,
  });

  @override
  State<CbzViewerScreen> createState() => _CbzViewerScreenState();
}

class _CbzViewerScreenState extends State<CbzViewerScreen> {
  late File _effectiveFile;
  List<File> _images = [];
  PageController? _pageController;
  int _currentIndex = 0;
  bool _loading = true;
  bool _extracting = false;
  String? _error;
  double _downloadProgress = 0.0;
  double _extractProgress = 0.0; // Rough extract %

  String get _pageKey => 'cbz_page_${widget.identifier}_${_safeName()}';
  String _safeName() =>
      safeFileName(widget.filenameHint ?? p.basename(_effectiveFile.path));

  @override
  void initState() {
    super.initState();
    _resolveFileAndExtract();
  }

  Future<void> _resolveFileAndExtract() async {
    setState(() {
      _loading = true;
      _error = null;
      _downloadProgress = 0.0;
      _extractProgress = 0.0;
    });

    try {
      // CASE 1: Local file
      if (widget.cbzFile != null && await widget.cbzFile!.exists()) {
        _effectiveFile = widget.cbzFile!;
        await _loadSavedPage();
        await _extractImages();
        return;
      }

      // CASE 2: Download from URL to PERSISTENT CACHE 🚀
      if (widget.url != null && widget.url!.isNotEmpty) {
        final fileName =
            widget.filenameHint ??
            p.basename(widget.url!).split('?').first.split('#').first;
        _effectiveFile = await cacheFileForUrl(
          widget.url!,
          filenameHint: fileName,
        ); // ← FIXED: Cache!

        if (!await _effectiveFile.exists() ||
            (await _effectiveFile.length()) == 0) {
          await downloadWithCache(
            url: widget.url!,
            filenameHint: fileName,
            onProgress: (received, total) {
              if (total != null && total > 0) {
                final p = received / total;
                ifMounted(this, () => setState(() => _downloadProgress = p));
              }
            },
          );
        }
        await _loadSavedPage();
        await _extractImages();
        return;
      }

      throw Exception('No valid CBZ source');
    } catch (e) {
      ifMounted(this, () {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadSavedPage() async {
    if (widget.identifier == null) return;
    final prefs = await SharedPreferences.getInstance();
    _currentIndex = prefs.getInt(_pageKey) ?? 0;
  }

  Future<void> _savePage(int index) async {
    if (widget.identifier == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pageKey, index);
  }

  Future<void> _extractImages() async {
    setState(() => _extracting = true);
    try {
      final cache = await appCacheDir();
      final dirName = 'cbz_${_effectiveFile.path.hashCode}';
      final dir = Directory(p.join(cache.path, dirName));
      if (!await dir.exists()) await dir.create(recursive: true);

      final imageReg = RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false);
      final manifestPath = p.join(dir.path, '.manifest.json');
      final manifestFile = File(manifestPath);

      // 🚀 NEW: SKIP RE-EXTRACTION CHECK
      List<File> potentialImages = [];
      if (await manifestFile.exists()) {
        final manifestContent = await manifestFile.readAsString();
        final expectedNames =
            (json.decode(manifestContent) as List).cast<String>()..sort();
        potentialImages =
            dir
                .listSync()
                .where(
                  (e) => e is File && imageReg.hasMatch(p.basename(e.path)),
                )
                .cast<File>()
                .toList();
        potentialImages.sort((a, b) => a.path.compareTo(b.path));
        final actualNames =
            potentialImages.map((f) => p.basename(f.path)).toList()..sort();

        if (_listsEqual(expectedNames, actualNames)) {
          ifMounted(this, () {
            _images = potentialImages;
            _loading = false;
            _pageController = PageController(
              initialPage: _currentIndex.clamp(0, _images.length - 1),
            );
          });
          return; // ✅ INSTANT!
        }
      }

      // Extract (first time only)
      final bytes = await _effectiveFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final out = <File>[];

      int totalImages =
          archive.files
              .where((f) => f.isFile && imageReg.hasMatch(f.name))
              .length;
      int extracted = 0;

      for (final f in archive.files) {
        if (f.isFile) {
          final name = safeFileName(f.name);
          final file = File(p.join(dir.path, name));
          await file.writeAsBytes(f.content as List<int>);
          if (imageReg.hasMatch(name)) {
            out.add(file);
            extracted++;
            if (totalImages > 0) {
              _extractProgress = extracted / totalImages;
              ifMounted(this, () => setState(() {}));
            }
          }
        }
      }

      out.sort((a, b) => a.path.compareTo(b.path));

      // 🚀 Save manifest
      final imageNames = out.map((f) => p.basename(f.path)).toList()..sort();
      await manifestFile.writeAsString(json.encode(imageNames));

      ifMounted(this, () {
        _images = out;
        _loading = false;
        _pageController = PageController(
          initialPage: _currentIndex.clamp(0, out.length - 1),
        );
      });
    } catch (e) {
      ifMounted(this, () {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      ifMounted(this, () => _extracting = false);
    }
  }

  bool _listsEqual(List<String> a, List<String> b) {
    // 🚀 Deterministic check
    if (a.length != b.length) return false;
    return a.join(',') == b.join(',');
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(widget.title),
      actions:
          _images.isNotEmpty
              ? [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${_currentIndex + 1}/${_images.length} (${((_currentIndex / _images.length) * 100).round()}%)',
                    ),
                  ),
                ),
              ]
              : null,
    );

    // Download screen
    if (_downloadProgress > 0 && _downloadProgress < 1) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 16),
              Text(
                '${(_downloadProgress * 100).toStringAsFixed(0)}% Downloading...',
              ),
            ],
          ),
        ),
      );
    }

    // Extract screen
    if (_extracting) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: _extractProgress),
              const SizedBox(height: 16),
              Text(
                'Extracting ${_images.length} pages... ${(_extractProgress * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
        ),
      );
    }

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _resolveFileAndExtract,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_images.isEmpty) {
      body = const Center(child: Text('No images found'));
    } else {
      body = PageView.builder(
        controller: _pageController,
        itemCount: _images.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _savePage(index);
        },
        itemBuilder:
            (context, index) => InteractiveViewer(
              child: Image.file(_images[index], fit: BoxFit.contain),
            ),
      );
    }

    return Scaffold(appBar: appBar, body: body);
  }
}
