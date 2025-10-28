// epub_viewer_screen.dart
import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

class EpubViewerScreen extends StatefulWidget {
  final String url;
  final String? filenameHint;
  final String identifier;
  final String title;

  const EpubViewerScreen({
    super.key,
    required this.url,
    this.filenameHint,
    required this.identifier,
    required this.title,
  });

  @override
  State<EpubViewerScreen> createState() => _EpubViewerScreenState();
}

class _EpubViewerScreenState extends State<EpubViewerScreen> {
  final _controller = EpubController();

  File? _localFile;
  bool _loading = true;
  double _downloadProgress = 0.0;
  String? _error;
  String? _initialCfi;
  double _currentProgress = 0.0; // ← Track progress from onRelocated

  String get _cfiKey => 'epub_cfi_${widget.identifier}_${_safeFileName()}';
  String _safeFileName() {
    final name =
        widget.filenameHint ??
        (_localFile?.path.split('/').last ?? 'book.epub');
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_').toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _loadAndOpen();
  }

  Future<void> _loadAndOpen() async {
    setState(() {
      _loading = true;
      _error = null;
      _downloadProgress = 0.0;
      _currentProgress = 0.0;
    });

    try {
      _localFile = await downloadWithCache(
        url: widget.url,
        filenameHint: widget.filenameHint,
        onProgress: (p) => setState(() => _downloadProgress = p * 0.6),
      );

      final prefs = await SharedPreferences.getInstance();
      _initialCfi = prefs.getString(_cfiKey);

      await RecentProgressService.instance.touch(
        id: '${widget.identifier}_${_safeFileName()}',
        title: widget.title,
        thumb: null,
        kind: 'epub',
        fileUrl: widget.url,
        fileName: widget.filenameHint ?? _localFile!.path.split('/').last,
      );

      setState(() {
        _loading = false;
        _downloadProgress = 1.0;
      });
    } catch (e) {
      ifMounted(this, () {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _handleRelocated(EpubLocation loc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cfiKey, loc.startCfi);

    setState(() => _currentProgress = loc.progress); // ← Update UI

    await RecentProgressService.instance.updateEpub(
      id: '${widget.identifier}_${_safeFileName()}',
      title: widget.title,
      thumb: null,
      page: 0,
      total: 0,
      percent: loc.progress,
      cfi: loc.startCfi,
      fileUrl: widget.url,
      fileName: widget.filenameHint ?? _localFile!.path.split('/').last,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(widget.title),
      actions: [
        if (!_loading)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${(_currentProgress * 100).toStringAsFixed(0)}%'),
            ),
          ),
      ],
    );

    if (_loading) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
              ),
              const SizedBox(height: 16),
              Text(
                _downloadProgress < 0.6 ? 'Downloading...' : 'Opening EPUB...',
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 8),
              Text(_error!),
              FilledButton(onPressed: _loadAndOpen, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: EpubViewer(
        epubSource: EpubSource.fromFile(_localFile!),
        epubController: _controller,
        initialCfi: _initialCfi,
        displaySettings: EpubDisplaySettings(
          flow: EpubFlow.paginated,
          snap: true,
          theme: EpubTheme(
            themeType:
                Theme.of(context).brightness == Brightness.dark
                    ? EpubThemeType.dark
                    : EpubThemeType.light,
          ),
        ),
        onRelocated: _handleRelocated,
      ),
    );
  }
}
