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

  PDFViewController? _pdfController;

  bool _isScrubbing = false;
  double _scrubPage = 0;

  // Bookmarks as 0-based page indices
  Set<int> _bookmarks = {};

  String get _progressId => widget.identifier;

  /// Unique resume key per *identifier + file*, so different PDFs don’t clash.
  String get _resumeKey {
    final parts = <String>['pdf_page', widget.identifier];

    if (widget.filenameHint != null && widget.filenameHint!.isNotEmpty) {
      parts.add(widget.filenameHint!);
    } else if (widget.url != null && widget.url!.isNotEmpty) {
      final last = Uri.tryParse(widget.url!)?.pathSegments.last;
      parts.add(last ?? widget.url!);
    } else if (widget.file != null) {
      final last = widget.file!.path.split(Platform.pathSeparator).last;
      parts.add(last);
    }

    return parts.join('_');
    // Example: pdf_page_mars_attacks_1993_issue_01.pdf
  }

  // Separate key for bookmarks for this PDF
  String get _bookmarksKey => '${_resumeKey}_bookmarks';

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
      // Use the *per-file* resume key. Defaults to 0 (page index 0 == page 1).
      final saved = prefs.getInt(_resumeKey) ?? 0;
      _defaultPage = saved;
      _currentPage = saved;
      _scrubPage = saved.toDouble();

      // Load bookmarks for this PDF
      final bmStrings = prefs.getStringList(_bookmarksKey) ?? const [];
      _bookmarks =
          bmStrings
              .map((s) => int.tryParse(s))
              .where((v) => v != null)
              .cast<int>()
              .toSet();

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

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _bookmarksKey,
      _bookmarks.map((e) => e.toString()).toList(),
    );
  }

  // Bottom sheet for "Go to page" + "Bookmark" (triggered by long-press)
  Future<void> _showPageActionsSheet() async {
    if (_totalPages <= 0) return;

    final isBookmarked = _bookmarks.contains(_currentPage);
    final currentLabel = 'Page ${_currentPage + 1}';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent, // so we can draw rounded container
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 20,
                  color: Colors.black.withOpacity(0.2),
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                // drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),

                ListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add,
                      size: 18,
                      color: colors.primary,
                    ),
                  ),
                  title: Text(
                    isBookmarked
                        ? 'Remove bookmark on $currentLabel'
                        : 'Add bookmark on $currentLabel',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop('bookmark'),
                ),

                const Divider(height: 1),

                ListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.secondary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tag, size: 18, color: colors.secondary),
                  ),
                  title: Text(
                    'Go to page…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop('goto'),
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'bookmark') {
      _toggleBookmarkForPage(_currentPage);
    } else if (result == 'goto') {
      _showGotoPageDialog();
    }
  }

  void _toggleBookmarkForPage(int page, {bool showSnackBar = true}) async {
    setState(() {
      if (_bookmarks.contains(page)) {
        _bookmarks.remove(page);
      } else {
        _bookmarks.add(page);
      }
    });
    await _saveBookmarks();

    if (!mounted || !showSnackBar) return;

    final isNowBookmarked = _bookmarks.contains(page);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isNowBookmarked
              ? 'Bookmarked page ${page + 1}'
              : 'Removed bookmark on page ${page + 1}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showGotoPageDialog() async {
    if (_totalPages <= 0) return;

    final controller = TextEditingController(text: '${_currentPage + 1}');
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final page = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Go to page',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.onSurface),
            decoration: InputDecoration(
              hintText: '1 – $_totalPages',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final raw = int.tryParse(controller.text.trim());
                if (raw == null) {
                  Navigator.of(ctx).pop();
                  return;
                }
                final target = raw.clamp(1, _totalPages) - 1; // 0-based
                Navigator.of(ctx).pop(target);
              },
              child: const Text('Go'),
            ),
          ],
        );
      },
    );

    if (page == null || !mounted) return;

    if (_pdfController != null) {
      await _pdfController!.setPage(page);
    }
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

          // Page indicator (still can long-press here too if you like)
          if (_totalPages > 0)
            GestureDetector(
              onLongPress: _showPageActionsSheet,
              child: Text(
                '${_currentPage + 1}/$_totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  // Bottom scrubber: floating rounded bar with page numbers + bookmark icons.
  Widget _buildBottomScrubber() {
    if (_totalPages <= 1) return const SizedBox.shrink();

    final min = 0.0;
    final max = (_totalPages - 1).toDouble();
    final value = _scrubPage.clamp(min, max);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page numbers row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${value.round() + 1}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                '$_totalPages',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Floating pill with slider + bookmark markers
          SizedBox(
            height: 40,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pillWidth = constraints.maxWidth;
                const horizontalPadding = 16.0;
                final trackWidth = pillWidth - (horizontalPadding * 2);

                final children = <Widget>[];

                // Pill background + slider
                children.add(
                  Container(
                    width: pillWidth,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 12,
                          color: Colors.black.withOpacity(0.12),
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    alignment: Alignment.center,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        value: value,
                        min: min,
                        max: max > min ? max : min + 1,
                        onChangeStart: (_) {
                          setState(() => _isScrubbing = true);
                        },
                        onChanged: (v) {
                          setState(() => _scrubPage = v);
                        },
                        onChangeEnd: (v) async {
                          if (_totalPages <= 0) return;
                          final targetPage = v.round().clamp(
                            0,
                            _totalPages - 1,
                          ); // 0-based
                          setState(() {
                            _isScrubbing = false;
                            _scrubPage = targetPage.toDouble();
                          });
                          if (_pdfController != null) {
                            await _pdfController!.setPage(targetPage);
                          }
                        },
                      ),
                    ),
                  ),
                );

                // Bookmark icons above the track (inside same pill area)
                if (_bookmarks.isNotEmpty && _totalPages > 1) {
                  for (final page in _bookmarks) {
                    if (page < 0 || page >= _totalPages) continue;

                    final t = page / (_totalPages - 1);
                    final dx = horizontalPadding + t * trackWidth;

                    children.add(
                      Positioned(
                        left: dx - 9, // center icon horizontally
                        top: 4, // a bit above the track
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () async {
                            if (_pdfController == null) return;

                            if (page == _currentPage) {
                              // tapping bookmark on current page removes it
                              _toggleBookmarkForPage(page);
                            } else {
                              await _pdfController!.setPage(page);
                            }
                          },
                          child: Icon(
                            Icons.bookmark,
                            size: 18,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    );
                  }
                }

                return Stack(clipBehavior: Clip.none, children: children);
              },
            ),
          ),
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
        onViewCreated: (controller) {
          _pdfController = controller;
          // Extra safety: ensure we land on the resumed page.
          if (_defaultPage > 0) {
            controller.setPage(_defaultPage);
          }
        },
        onRender: (pages) {
          if (pages == null || pages == 0) return;
          setState(() {
            _totalPages = pages;
            // Ensure current/scrub are within range
            _currentPage = _defaultPage.clamp(0, pages - 1);
            _scrubPage = _currentPage.toDouble();

            // Prune invalid bookmark indices
            _bookmarks =
                _bookmarks.where((p) => p >= 0 && p < _totalPages).toSet();
          });

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
              if (!_isScrubbing) {
                _scrubPage = page.toDouble();
              }
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
                  _localFile?.path.split(Platform.pathSeparator).last,
            );
          }
        },
        onError: (e) => setState(() => _error = e.toString()),
        onPageError: (page, e) {
          setState(() => _error = 'Page ${(page ?? 0) + 1}: $e');
        },
      );

      // <<< KEY PART: long-press on the PAGE (PDF area) >>>
      final viewerWithLongPress = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _showPageActionsSheet,
        child: viewer,
      );

      body = Stack(
        fit: StackFit.expand,
        children: [
          viewerWithLongPress,
          // Top gradient bar with back + page indicator
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
          // Bottom scrubber for quick navigation + bookmarks
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomScrubber(),
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
