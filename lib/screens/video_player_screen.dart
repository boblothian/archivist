import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_to_airplay/flutter_to_airplay.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../net.dart';
import '../services/recent_progress_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final File? file;
  final String? url; // nullable if playing via queue
  final String identifier;
  final String title;
  final int? startPositionMs;

  // Queue support (all optional)
  final List<String>? queue; // URLs
  final Map<String, String>? queueTitles; // url -> title
  final int? startIndex; // index into `queue`

  /// Optional: if this player was opened from a "continue" card and you want
  /// the back button to go to a video album / item screen instead of just
  /// popping, provide [albumScreenBuilder] and set [navigateToAlbumOnExit].
  final WidgetBuilder? albumScreenBuilder;
  final bool navigateToAlbumOnExit;

  VideoPlayerScreen({
    super.key,
    this.file,
    this.url,
    required this.identifier,
    required this.title,
    this.startPositionMs,
    this.queue,
    this.queueTitles,
    this.startIndex,
    this.albumScreenBuilder,
    this.navigateToAlbumOnExit = false,
  }) : assert(
         file != null || url != null || ((queue ?? const []).isNotEmpty),
         'Provide a file, a url, or a non-empty queue',
       );

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // ─── Retain controllers when leaving on iOS to keep AirPlay alive ───
  static VideoPlayerController? _retainedVideo;
  static ChewieController? _retainedChewie;
  bool _keepAliveForAirPlay = false;

  // Queue state
  List<String> _urls = const [];
  Map<String, String> _titles = const {};
  int _queueIndex = 0;

  String get _currentUrl {
    if (_urls.isNotEmpty) {
      final i = _queueIndex.clamp(0, _urls.length - 1);
      return _urls[i];
    }
    return widget.url ?? '';
  }

  String get _currentTitle => _titles[_currentUrl] ?? widget.title;
  bool get _hasHttpUrl => _currentUrl.toLowerCase().startsWith('http');

  // Progress
  int _lastPosMs = 0;
  int _lastDurMs = 0;
  bool _popped = false;

  // State flags
  bool _wasBuffering = false;
  bool _wasPlaying = false;

  // Local player
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  // Chromecast
  StreamSubscription<GoogleCastSession?>? _gcSessionSub;
  StreamSubscription? _gcMediaStatusSub;
  bool _isCastingChromecast = false;
  bool _chromecastInitAttempted = false;

  // DLNA (Android only)
  final MediaCastDlnaApi _dlna = MediaCastDlnaApi();
  List<DlnaDevice> _dlnaDevices = [];
  bool _dlnaReady = false;
  bool _isCastingDlna = false;
  DeviceUdn? _activeDlnaUdn;
  Timer? _dlnaRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initQueueState();
    _initializePlayerForCurrent(initial: true);
    _initDlna();
    WakelockPlus.enable();
  }

  void _initQueueState() {
    if (widget.queue != null && widget.queue!.isNotEmpty) {
      _urls = List<String>.from(widget.queue!);
      _titles = Map<String, String>.from(widget.queueTitles ?? const {});
      _queueIndex = (widget.startIndex ?? 0).clamp(0, _urls.length - 1);
    } else if (widget.url != null) {
      _urls = [widget.url!];
      _titles = Map<String, String>.from(widget.queueTitles ?? const {});
      _queueIndex = 0;
    } else {
      _urls = const [];
      _titles = const {};
      _queueIndex = 0;
    }
  }

  @override
  void dispose() {
    if (!_popped) {
      _saveProgress(); // best-effort
    }

    // iOS AirPlay: retain controllers instead of disposing if user opted in
    if (Platform.isIOS && _keepAliveForAirPlay && _videoController != null) {
      try {
        _videoController?.removeListener(_onTick);
      } catch (_) {}
      _retainedVideo ??= _videoController;
      _retainedChewie ??= _chewieController;
      _videoController = null;
      _chewieController = null;
    } else {
      _disposePlayers();
    }

    WakelockPlus.disable();

    _gcSessionSub?.cancel();
    _gcMediaStatusSub?.cancel();
    try {
      GoogleCastSessionManager.instance.endSessionAndStopCasting();
      GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (_) {}

    _dlnaRefreshTimer?.cancel();
    _stopDlnaDiscovery();

    super.dispose();
  }

  void _disposePlayers() {
    try {
      _videoController?.removeListener(_onTick);
    } catch (_) {}
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  // ───────────────────── Chromecast (lazy init) ─────────────────────
  Future<void> _initChromecast() async {
    if (_chromecastInitAttempted) return; // already tried
    _chromecastInitAttempted = true;

    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;

      GoogleCastOptions? options;
      if (Platform.isIOS) {
        options = IOSGoogleCastOptions(
          GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
        );
      } else if (Platform.isAndroid) {
        options = GoogleCastOptionsAndroid(appId: appId);
      }

      if (options != null) {
        await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      }

      try {
        await GoogleCastDiscoveryManager.instance.startDiscovery();
      } catch (_) {}

      _gcSessionSub = GoogleCastSessionManager.instance.currentSessionStream
          .listen((s) {
            if (s != null) {
              _gcMediaStatusSub?.cancel();
              _gcMediaStatusSub = GoogleCastRemoteMediaClient
                  .instance
                  .mediaStatusStream
                  .listen((status) {
                    final playingStates = {
                      CastMediaPlayerState.playing,
                      CastMediaPlayerState.buffering,
                      CastMediaPlayerState.paused,
                    };
                    setState(() {
                      _isCastingChromecast =
                          status != null &&
                          playingStates.contains(status.playerState);
                    });
                  });
              _castToChromecast();
            } else {
              setState(() => _isCastingChromecast = false);
            }
          });
    } catch (e) {
      debugPrint('Chromecast init error (ignored): $e');
    }
  }

  Duration get _currentPositionForCast {
    if (_videoController != null) {
      return _videoController!.value.position;
    }
    return Duration(milliseconds: _lastPosMs);
  }

  Future<void> _castToChromecast() async {
    if (!_hasHttpUrl) {
      debugPrint('Cast: abort — current URL is not HTTP: $_currentUrl');
      return;
    }

    final url = _currentUrl;
    final info = GoogleCastMediaInformation(
      contentId: url,
      contentUrl: Uri.parse(url),
      contentType: _guessMime(url),
      streamType: _guessStreamType(url),
      metadata: GoogleCastGenericMediaMetadata(
        title: _currentTitle,
        subtitle: 'Archive.org',
        images: [
          GoogleCastImage(
            url: Uri.parse(
              'https://archive.org/services/img/${widget.identifier}',
            ),
            height: 360,
            width: 480,
          ),
        ],
      ),
    );

    try {
      if (_videoController?.value.isPlaying == true) {
        await _videoController!.pause();
      }
      final pos = _currentPositionForCast;
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        info,
        autoPlay: true,
        playPosition: pos,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Chromecast failed: $e')));
    }
  }

  // ───────────────────── DLNA ─────────────────────
  Future<void> _initDlna() async {
    if (!Platform.isAndroid) return;
    try {
      await _dlna.initializeUpnpService();
      final ok = await _dlna.isUpnpServiceInitialized();
      setState(() => _dlnaReady = ok);
      if (ok) _startDlnaDiscovery();
    } catch (e) {
      debugPrint('DLNA init error: $e');
    }
  }

  Future<void> _startDlnaDiscovery() async {
    if (!_dlnaReady) return;
    try {
      await _dlna.startDiscovery(
        DiscoveryOptions(
          timeout: DiscoveryTimeout(seconds: 10),
          searchTarget: SearchTarget(target: 'upnp:rootdevice'),
        ),
      );

      _dlnaDevices = await _dlna.getDiscoveredDevices();
      if (mounted) setState(() {});

      _dlnaRefreshTimer?.cancel();
      _dlnaRefreshTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        final list = await _dlna.getDiscoveredDevices();
        if (mounted) setState(() => _dlnaDevices = list);
        if (t.tick >= 6) {
          t.cancel();
          _stopDlnaDiscovery();
        }
      });
    } catch (e) {
      debugPrint('DLNA discovery error: $e');
    }
  }

  Future<void> _stopDlnaDiscovery() async {
    try {
      await _dlna.stopDiscovery();
    } catch (_) {}
  }

  Future<void> _castToDlna(DlnaDevice device) async {
    if (!_hasHttpUrl) {
      debugPrint('DLNA: abort — current URL is not HTTP: $_currentUrl');
      return;
    }

    final url = _currentUrl;
    final udn = device.udn;
    String? resolution;
    TimeDuration? duration;

    if (_videoController != null && _videoController!.value.isInitialized) {
      final size = _videoController!.value.size;
      if (size.width > 0 && size.height > 0) {
        resolution = '${size.width.toInt()}x${size.height.toInt()}';
      }
      final d = _videoController!.value.duration;
      if (d.inMilliseconds > 0) {
        duration = TimeDuration(seconds: d.inSeconds);
      }
    }

    final meta = VideoMetadata(
      title: _currentTitle,
      upnpClass: 'object.item.videoItem.movie',
      resolution: resolution,
      duration: duration,
      genre: null,
    );

    try {
      if (_videoController?.value.isPlaying == true) {
        await _videoController!.pause();
      }
      await _dlna.setMediaUri(udn, Url(value: url), meta);
      await _dlna.play(udn);

      await _stopDlnaDiscovery();
      _dlnaRefreshTimer?.cancel();
      _dlnaRefreshTimer = null;

      if (mounted) {
        setState(() {
          _isCastingDlna = true;
          _activeDlnaUdn = udn;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('DLNA failed: $e')));
    }
  }

  Future<void> _stopDlnaPlayback() async {
    if (_activeDlnaUdn == null) return;
    try {
      await _dlna.stop(_activeDlnaUdn!);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isCastingDlna = false;
      _activeDlnaUdn = null;
    });
  }

  // ───────────────────── Local player ─────────────────────
  Future<void> _initializePlayerForCurrent({bool initial = false}) async {
    // If we retained controllers (iOS keep-alive), reuse them.
    if (Platform.isIOS && _retainedVideo != null && _retainedChewie != null) {
      _videoController = _retainedVideo;
      _chewieController = _retainedChewie;
      _retainedVideo = null;
      _retainedChewie = null;

      _videoController?.removeListener(_onTick);
      _videoController?.addListener(_onTick);

      _wasBuffering = _videoController!.value.isBuffering;
      _wasPlaying = _videoController!.value.isPlaying;
      if (mounted) setState(() {});
      return;
    }

    // Fresh controllers
    _disposePlayers();

    if (widget.file != null && _urls.isEmpty) {
      _videoController = VideoPlayerController.file(widget.file!);
    } else if (_currentUrl.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_currentUrl),
        httpHeaders: Net.headers,
      );
    } else {
      throw StateError('No video source available.');
    }

    _videoController!.addListener(_onTick);
    await _videoController!.initialize();
    await _videoController!.setLooping(false);

    if (initial && (widget.startPositionMs ?? 0) > 0) {
      await _videoController!.seekTo(
        Duration(milliseconds: widget.startPositionMs!),
      );
    }

    _wasBuffering = _videoController!.value.isBuffering;
    _wasPlaying = _videoController!.value.isPlaying;

    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      showControls: true,
    );

    if (mounted) setState(() {});
  }

  void _onTick() {
    if (_videoController == null) return;

    final v = _videoController!.value;
    _lastPosMs = v.position.inMilliseconds;
    _lastDurMs = v.duration.inMilliseconds;

    final ended =
        v.isInitialized &&
        !v.isPlaying &&
        !v.isBuffering &&
        v.duration.inMilliseconds > 0 &&
        v.position >= v.duration &&
        _queueIndex < _urls.length - 1;

    if (ended) {
      _playNextInQueue();
      return;
    }

    if (_wasBuffering != v.isBuffering || _wasPlaying != v.isPlaying) {
      setState(() {
        _wasBuffering = v.isBuffering;
        _wasPlaying = v.isPlaying;
      });
    }
  }

  Future<void> _playNextInQueue() async {
    if (_queueIndex >= _urls.length - 1) return;
    _queueIndex++;
    await _initializePlayerForCurrent();
  }

  Future<void> _playPrevInQueue() async {
    if (_queueIndex == 0) return;
    _queueIndex--;
    await _initializePlayerForCurrent();
  }

  // ───────────────────── Back/Pop handling (keep AirPlay) ─────────────────────
  Future<bool> _onWillPop() async {
    if (Platform.isIOS) {
      final isPlaying = _videoController?.value.isPlaying ?? false;
      if (isPlaying) {
        final keepPlaying =
            await showDialog<bool>(
              context: context,
              builder:
                  (ctx) => AlertDialog(
                    title: const Text('Keep playing on AirPlay?'),
                    content: const Text(
                      'You can leave this screen and keep the video playing on your TV.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Stop & Go Back'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Keep Playing'),
                      ),
                    ],
                  ),
            ) ??
            false;
        _keepAliveForAirPlay = keepPlaying || _keepAliveForAirPlay;
      }
    }

    return _handlePopWithProgress();
  }

  // ───────────────────── UI ─────────────────────
  @override
  Widget build(BuildContext context) {
    final bool isInitialized =
        _chewieController?.videoPlayerController.value.isInitialized ?? false;

    final bool isCasting = _isCastingChromecast || _isCastingDlna;

    final bool showBuffering =
        isInitialized &&
        !isCasting &&
        (_videoController?.value.isBuffering ?? false) &&
        !(_videoController?.value.isPlaying ?? false);

    final bool hasQueue = _urls.length > 1;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_currentTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _onWillPop(),
          ),
          actions: [
            if (hasQueue)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${_queueIndex + 1}/${_urls.length}'),
                ),
              ),
            if (Platform.isIOS)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: AirPlayRoutePickerView(
                    tintColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                    activeTintColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            if (!Platform.isIOS)
              IconButton(
                tooltip: 'Cast',
                icon: Icon(isCasting ? Icons.cast_connected : Icons.cast),
                onPressed: !_hasHttpUrl ? null : _openCastPicker,
              ),
            if (_isCastingDlna)
              IconButton(
                tooltip: 'Stop DLNA',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () async => _stopDlnaPlayback(),
              ),
            if (_isCastingChromecast)
              IconButton(
                tooltip: 'Disconnect Chromecast',
                icon: const Icon(Icons.close_fullscreen),
                onPressed: () async {
                  try {
                    await GoogleCastSessionManager.instance
                        .endSessionAndStopCasting();
                  } catch (_) {}
                },
              ),
          ],
        ),
        body: Stack(
          children: [
            if (!isInitialized)
              const Center(child: CircularProgressIndicator())
            else if (isCasting)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cast_connected, size: 64),
                    SizedBox(height: 16),
                    Text('Casting…'),
                  ],
                ),
              )
            else
              Chewie(
                key: ValueKey(
                  _currentUrl.isNotEmpty
                      ? _currentUrl
                      : widget.file?.path ?? widget.identifier,
                ),
                controller: _chewieController!,
              ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: GoogleCastMiniController(),
            ),
            if (showBuffering) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Future<bool> _handlePopWithProgress() async {
    if (_popped) return false;
    _popped = true;
    if (!mounted) return false;

    await _saveProgress();

    // If we were opened from a "continue" card and we have an album
    // screen to go to, replace this screen with that.
    if (widget.navigateToAlbumOnExit && widget.albumScreenBuilder != null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: widget.albumScreenBuilder!));
    } else {
      Navigator.of(
        context,
      ).pop(<String, int>{'positionMs': _lastPosMs, 'durationMs': _lastDurMs});
    }

    return false;
  }

  // Combined picker (Chromecast + DLNA)
  Future<void> _openCastPicker() async {
    await _initChromecast();
    try {
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (_) {}
    if (_dlnaReady) _startDlnaDiscovery();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.cast),
                    title: const Text('Cast to device'),
                    subtitle: const Text(
                      'Chromecast or DLNA devices on your Wi-Fi',
                    ),
                    trailing: IconButton(
                      tooltip: 'Refresh',
                      onPressed: () {
                        GoogleCastDiscoveryManager.instance.startDiscovery();
                        if (_dlnaReady) _startDlnaDiscovery();
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.tv, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Chromecast devices',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 160,
                    child: StreamBuilder<List<GoogleCastDevice>>(
                      stream:
                          GoogleCastDiscoveryManager.instance.devicesStream
                              .asBroadcastStream(),
                      builder: (context, snap) {
                        final devices = snap.data ?? const <GoogleCastDevice>[];
                        if (devices.isEmpty) {
                          return const Center(
                            child: Text('No Chromecast devices found'),
                          );
                        }
                        return ListView.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final d = devices[i];
                            return ListTile(
                              leading: const Icon(Icons.cast),
                              title: Text(d.friendlyName),
                              subtitle: Text(d.modelName ?? d.deviceID),
                              onTap: () async {
                                try {
                                  await GoogleCastSessionManager.instance
                                      .startSessionWithDevice(d);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Connect failed: $e'),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.dns, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'DLNA devices',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        if (!Platform.isAndroid)
                          const Text(
                            '(Android only)',
                            style: TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child:
                        !_dlnaReady
                            ? const Center(
                              child: Text(
                                'DLNA not available on this platform',
                              ),
                            )
                            : (_dlnaDevices.isEmpty
                                ? const Center(
                                  child: Text('Searching for DLNA devices…'),
                                )
                                : ListView.separated(
                                  itemCount: _dlnaDevices.length,
                                  separatorBuilder:
                                      (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final dev = _dlnaDevices[i];
                                    return ListTile(
                                      leading: const Icon(Icons.tv_outlined),
                                      title: Text(dev.friendlyName),
                                      subtitle: Text(dev.deviceType),
                                      onTap: () async {
                                        try {
                                          await _castToDlna(dev);
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('DLNA failed: $e'),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                )),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProgress() async {
    if (_videoController != null && _videoController!.value.isInitialized) {
      _lastPosMs = _videoController!.value.position.inMilliseconds;
      _lastDurMs = _videoController!.value.duration.inMilliseconds;
    }

    final String fileUrl =
        widget.file != null ? 'file://${widget.file!.path}' : _currentUrl;

    final String fileName =
        widget.file != null
            ? widget.file!.path.split(Platform.pathSeparator).last
            : (Uri.tryParse(_currentUrl)?.pathSegments.isNotEmpty ?? false)
            ? Uri.parse(_currentUrl).pathSegments.last
            : widget.title;

    try {
      await RecentProgressService.instance.updateVideo(
        id: widget.identifier,
        title: _currentTitle,
        thumb: null,
        fileUrl: fileUrl,
        fileName: fileName,
        positionMs: _lastPosMs,
        durationMs: _lastDurMs,
      );
    } catch (e) {
      debugPrint('VideoPlayerScreen: failed to save progress: $e');
    }
  }

  String _guessMime(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.m3u8')) return 'application/x-mpegurl';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    return 'video/*';
  }

  CastMediaStreamType _guessStreamType(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.m3u8')) return CastMediaStreamType.live; // HLS
    return CastMediaStreamType.buffered;
  }
}
