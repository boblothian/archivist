// pdf_viewer_screen.dart
import 'dart:io';

import 'package:archivereader/services/recent_progress_service.dart';
import 'package:fade_shimmer/fade_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils.dart';

class PdfViewerScreen extends StatefulWidget {
  final File? file;
  final String? url;
  final String? filenameHint;
  final String identifier;
  final String title;
  final String? thumbUrl;

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
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  File? _localFile;
  bool _loading = true;
  double _progress = 0;
  String? _error;
  int _currentPage = 0;
  int _totalPages = 0;
  int _defaultPage = 0;

  String get _progressId => widget.identifier;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    _loadPdfAndResume();
  }

  @override
  void dispose() {
    _exitFullscreen();
    super.dispose();
  }

  // Fullscreen handling
  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // PDF loading & resume
  Future<void> _loadPdfAndResume() async {
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
          onProgress: (received, total) {
            if (total != null && total > 0) {
              final p = received / total;
              ifMounted(this, () => setState(() => _progress = p));
            }
          },
        );
      }

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

  // Fullscreen top bar: back + page indicator
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back',
            ),
          ),

          // Page indicator
          if (_totalPages > 0)
            Text(
              '${_currentPage + 1}/$_totalPages',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          // Animated Shimmer Background
          const FadeShimmer(
            width: double.infinity,
            height: double.infinity,
            highlightColor: Color(0xFF424242),
            baseColor: Color(0xFF212121),
            millisecondsDelay: 1500,
          ),

          // Loading Content (centered)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  _progress == 0
                      ? 'Preparing...'
                      : '${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.filenameHint != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.filenameHint!.split('/').last,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadPdfAndResume,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else {
      final viewer = PDFView(
        filePath: _localFile!.path,
        defaultPage: _defaultPage,
        enableSwipe: true,
        swipeHorizontal: true,
        pageFling: true,
        pageSnap: true,
        autoSpacing: true,
        onRender: (pages) {
          if (pages == null || pages == 0) return;
          setState(() => _totalPages = pages);

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
              thumb: widget.thumbUrl,
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

      body = Stack(
        fit: StackFit.expand,
        children: [
          viewer,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  bottom: 12,
                ),
                child: _buildTopBar(),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: Colors.black,
      body: Container(color: Colors.black, child: body),
    );
  }
}
