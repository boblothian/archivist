// pdf_viewer_screen.dart
import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

class PdfViewerScreen extends StatefulWidget {
  final File? file;
  final String? url;
  final String? filenameHint;
  final String identifier;
  final String title;
  final String? thumbUrl; // ← NEW

  const PdfViewerScreen({
    super.key,
    this.file,
    this.url,
    this.filenameHint,
    required this.identifier,
    required this.title,
    this.thumbUrl,
  }) : assert(file != null || url != null);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState(); // ← THIS WAS MISSING!
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  File? _localFile;
  bool _loading = true;
  double _progress = 0;
  String? _error;
  int _currentPage = 0;
  int _totalPages = 0;
  int _defaultPage = 0; // ← Set once

  String get _progressId => widget.identifier;

  @override
  void initState() {
    super.initState();
    _loadPdfAndResume();
  }

  Future<void> _loadPdfAndResume() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });

    try {
      // 1. Download file
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

      // 2. Read saved page
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('pdf_page_${widget.identifier}') ?? 0;
      _defaultPage = saved;

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
    await prefs.setInt('pdf_page_${widget.identifier}', page);
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(widget.title),
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
            FilledButton(
              onPressed: _loadPdfAndResume,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else {
      // ← SHOW PDF IMMEDIATELY
      body = PDFView(
        filePath: _localFile!.path,
        defaultPage: _defaultPage,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        onRender: (pages) {
          if (pages == null || pages == 0) return;
          setState(() => _totalPages = pages);

          // Save first touch
          RecentProgressService.instance.touch(
            id: _progressId,
            title: widget.title,
            thumb: null,
            kind: 'pdf',
            fileUrl: widget.url,
            fileName: widget.filenameHint,
          );

          final initPage = _defaultPage.clamp(0, pages - 1);
          RecentProgressService.instance.updatePdf(
            id: _progressId,
            title: widget.title,
            thumb: null,
            page: initPage + 1,
            total: pages,
            fileUrl: widget.url ?? _localFile?.path,
            fileName: widget.filenameHint ?? _localFile?.path.split('/').last,
          );
        },
        onPageChanged: (page, total) {
          if (page != null && total != null && total > 0) {
            setState(() {
              _currentPage = page;
              _totalPages = total;
            });
            _saveResume(page);

            RecentProgressService.instance.updatePdf(
              id: _progressId,
              title: widget.title,
              thumb: widget.thumbUrl, // ← USE IT!
              page: page + 1,
              total: total,
              fileUrl: widget.url ?? _localFile?.path,
              fileName: widget.filenameHint ?? _localFile?.path.split('/').last,
            );
          }
        },
        onError: (e) => setState(() => _error = e.toString()),
        onPageError: (page, e) {
          setState(() => _error = 'Page ${(page ?? 0) + 1}: $e');
        },
      );
    }

    return Scaffold(appBar: appBar, body: body);
  }
}
