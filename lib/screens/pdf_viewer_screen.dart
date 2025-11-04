// pdf_viewer_screen.dart
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ⬅️ for SystemChrome
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:pdfx/pdfx.dart';
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

  bool _useAnimatedPager = false;

  // ⬇️ Fullscreen state
  bool _isFullscreen = false;

  String get _progressId => widget.identifier;

  @override
  void initState() {
    super.initState();
    _loadPdfAndResume();
  }

  @override
  void dispose() {
    // Ensure system bars are restored if we leave while fullscreen
    _setSystemBars(visible: true);
    super.dispose();
  }

  Future<void> _setSystemBars({required bool visible}) async {
    if (visible) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _enterFullscreen() async {
    setState(() => _isFullscreen = true);
    await _setSystemBars(visible: false);
  }

  Future<void> _exitFullscreen() async {
    setState(() => _isFullscreen = false);
    await _setSystemBars(visible: true);
  }

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

  @override
  Widget build(BuildContext context) {
    // Hide AppBar in fullscreen so content truly fills the screen
    final appBar =
        _isFullscreen
            ? null
            : AppBar(
              title: Text(widget.title),
              actions: [
                if (_totalPages > 0)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('${_currentPage + 1}/$_totalPages'),
                    ),
                  ),
                IconButton(
                  tooltip:
                      _useAnimatedPager
                          ? 'Switch to normal view'
                          : 'Switch to animated view',
                  icon: Icon(
                    _useAnimatedPager
                        ? Icons.auto_awesome_motion
                        : Icons.auto_awesome,
                  ),
                  onPressed:
                      () => setState(
                        () => _useAnimatedPager = !_useAnimatedPager,
                      ),
                ),
                IconButton(
                  tooltip: 'Enter fullscreen',
                  icon: const Icon(Icons.fullscreen),
                  onPressed: _enterFullscreen,
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
      final viewer =
          _useAnimatedPager
              ? AnimatedPdfPager(
                filePath: _localFile!.path,
                initialPage: _defaultPage,
                onPageMetrics: (curr, total) {
                  setState(() {
                    _currentPage = curr;
                    _totalPages = total;
                  });
                  _saveResume(curr);
                  RecentProgressService.instance.updatePdf(
                    id: _progressId,
                    title: widget.title,
                    thumb: widget.thumbUrl,
                    page: curr + 1,
                    total: total,
                    fileUrl: widget.url ?? _localFile?.path,
                    fileName:
                        widget.filenameHint ?? _localFile?.path.split('/').last,
                  );
                },
                onFirstRender: (pages) {
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
                    fileName:
                        widget.filenameHint ?? _localFile?.path.split('/').last,
                  );
                },
              )
              : PDFView(
                filePath: _localFile!.path,
                defaultPage: _defaultPage,

                // Horizontal paging with snap + fling
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
                    fileName:
                        widget.filenameHint ?? _localFile?.path.split('/').last,
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
                      fileName:
                          widget.filenameHint ??
                          _localFile?.path.split('/').last,
                    );
                  }
                },
                onError: (e) => setState(() => _error = e.toString()),
                onPageError: (page, e) {
                  setState(() => _error = 'Page ${(page ?? 0) + 1}: $e');
                },
              );

      // ⬇️ When fullscreen, draw behind system bars and show only a tiny exit button
      body = Stack(
        fit: StackFit.expand,
        children: [
          // Avoid SafeArea in fullscreen; respect it otherwise.
          _isFullscreen ? viewer : SafeArea(child: viewer),
          if (_isFullscreen)
            Positioned(
              top: 20,
              right: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Exit fullscreen',
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  onPressed: _exitFullscreen,
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar:
          _isFullscreen, // content under status bar in fullscreen
      appBar: appBar,
      body: body,
      backgroundColor: Colors.black,
    );
  }
}

/// Animated page-by-page PDF viewer using pdfx (2.9.x) + SharedAxisTransition.
/// - Renders with PdfViewPinch and drives page changes via controller.jumpToPage
/// - Tap right/left sides or swipe to change page
class AnimatedPdfPager extends StatefulWidget {
  final String filePath;
  final int initialPage; // zero-based
  final void Function(int current, int total)? onPageMetrics;
  final void Function(int totalPages)? onFirstRender;

  const AnimatedPdfPager({
    super.key,
    required this.filePath,
    this.initialPage = 0,
    this.onPageMetrics,
    this.onFirstRender,
  });

  @override
  State<AnimatedPdfPager> createState() => _AnimatedPdfPagerState();
}

class _AnimatedPdfPagerState extends State<AnimatedPdfPager> {
  late PdfControllerPinch _controller;
  int _pageCount = 0;
  int _pageIndex = 0; // zero-based

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.filePath),
      initialPage: widget.initialPage + 1,
    );
    _initDocument();
  }

  Future<void> _initDocument() async {
    final doc = await PdfDocument.openFile(widget.filePath);
    _pageCount = doc.pagesCount;
    _pageIndex = widget.initialPage;
    widget.onFirstRender?.call(_pageCount);
    widget.onPageMetrics?.call(_pageIndex, _pageCount);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goTo(int newIndex) async {
    if (newIndex < 0 || newIndex >= _pageCount) return;
    setState(() => _pageIndex = newIndex);
    _controller.jumpToPage(newIndex + 1);
    widget.onPageMetrics?.call(_pageIndex, _pageCount);
  }

  @override
  Widget build(BuildContext context) {
    if (_pageCount == 0) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final w = MediaQuery.of(context).size.width;
        if (d.localPosition.dx > w * 0.6) {
          _goTo(_pageIndex + 1);
        } else if (d.localPosition.dx < w * 0.4) {
          _goTo(_pageIndex - 1);
        }
      },
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) _goTo(_pageIndex + 1);
        if (v > 200) _goTo(_pageIndex - 1);
      },
      child: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation, secondaryAnimation) {
          return SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.horizontal,
            fillColor: Theme.of(context).colorScheme.surface,
            child: child,
          );
        },
        // changing the key forces a transition; content switches because we jumpToPage(...)
        child: KeyedSubtree(
          key: ValueKey(_pageIndex),
          child: PdfViewPinch(
            controller: _controller,
            onDocumentLoaded: (doc) {
              _pageCount = doc.pagesCount;
              widget.onFirstRender?.call(_pageCount);
              widget.onPageMetrics?.call(_pageIndex, _pageCount);
            },
            onPageChanged: (page) {
              if (page != null) {
                setState(() => _pageIndex = page - 1);
                widget.onPageMetrics?.call(_pageIndex, _pageCount);
              }
            },
          ),
        ),
      ),
    );
  }
}
