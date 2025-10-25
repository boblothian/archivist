import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

class PdfViewerScreen extends StatefulWidget {
  final File? file; // if already downloaded
  final String? url; // OR download from URL
  final String? filenameHint; // cache filename when url is provided

  const PdfViewerScreen({super.key, this.file, this.url, this.filenameHint})
    : assert(file != null || url != null, 'Provide either file or url');

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  File? _localFile;
  bool _loading = true;
  double _progress = 0;
  String? _error;
  int _currentPage = 0;
  int _totalPages = 0;

  String get _resumeKey =>
      'pdf_resume_${_localFile?.path.hashCode ?? widget.url.hashCode}';

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });

    try {
      if (widget.file != null) {
        _localFile = widget.file;
      } else {
        _localFile = await downloadWithCache(
          url: widget.url!,
          filenameHint: widget.filenameHint,
          onProgress:
              (p) => ifMounted(this, () => setState(() => _progress = p)),
        );
      }
      ifMounted(this, () => setState(() => _loading = false));
    } catch (e) {
      ifMounted(this, () {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveResume(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_resumeKey, page);
  }

  Future<int?> _readResume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_resumeKey);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(widget.filenameHint ?? 'PDF'),
      actions: [
        if (_totalPages > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${_currentPage + 1}/$_totalPages'),
            ),
          ),
      ],
    );

    Widget body;
    if (_loading) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              _progress == 0
                  ? 'Preparing…'
                  : '${(_progress * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      );
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loadPdf, child: const Text('Retry')),
          ],
        ),
      );
    } else {
      body = FutureBuilder<int?>(
        future: _readResume(),
        builder: (context, snap) {
          final initial = (snap.data ?? 0).clamp(
            0,
            _totalPages == 0 ? 0 : _totalPages - 1,
          );
          return PDFView(
            filePath: _localFile!.path,
            defaultPage: initial,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            onRender: (pages) => setState(() => _totalPages = pages ?? 0),
            onViewCreated: (_) {},
            onPageChanged: (page, total) {
              if (page != null && total != null) {
                setState(() {
                  _currentPage = page;
                  _totalPages = total;
                });
                _saveResume(page);
              }
            },
            onError: (e) => setState(() => _error = e.toString()),
            onPageError: (page, e) => setState(() => _error = 'Page $page: $e'),
          );
        },
      );
    }

    return Scaffold(appBar: appBar, body: body);
  }
}
