import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';
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

  String get _progressId =>
      widget.filenameHint ??
      widget.url ??
      _localFile?.path ??
      'pdf-${_localFile.hashCode}';

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

  Future<bool> _downloadToFile(
    String url,
    File dst,
    void Function(double progress)? onProgress,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers.addAll(Net.headers); // ← IMPORTANT
      final resp = await client.send(req);

      if (resp.statusCode != 200) return false;

      final total = resp.contentLength ?? 0;
      int received = 0;
      final sink = dst.openWrite();

      await resp.stream
          .listen(
            (chunk) {
              sink.add(chunk);
              received += chunk.length;
              if (total > 0 && onProgress != null) {
                onProgress(received / total);
              }
            },
            onError: (_) async {
              await sink.close();
            },
            onDone: () async {
              await sink.close();
            },
            cancelOnError: true,
          )
          .asFuture(); // await completion

      // basic integrity check
      final len = await dst.length();
      return len > 0;
    } finally {
      client.close();
    }
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
            onRender: (pages) {
              setState(() => _totalPages = pages ?? 0);

              // tell the recent service we opened this PDF
              RecentProgressService.instance.updatePdf(
                id: _progressId,
                title: widget.filenameHint ?? 'PDF',
                thumb: null, // pass a thumb if you have one
                page: _currentPage + 1, // 1-based
                total: _totalPages,
              );
            },

            onPageChanged: (page, total) {
              if (page != null && total != null) {
                setState(() {
                  _currentPage = page;
                  _totalPages = total;
                });
                _saveResume(page);

                // also update global recent/progress
                RecentProgressService.instance.updatePdf(
                  id: _progressId,
                  title: widget.filenameHint ?? 'PDF',
                  thumb: null,
                  page: page + 1, // 1-based
                  total: total,
                );
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
