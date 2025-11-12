// lib/screens/video_player_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart'; // DLNA (Android only)
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../net.dart';

class VideoPlayerScreen extends StatefulWidget {
  final File? file;
  final String? url; // nullable if playing via queue
  final String identifier;
  final String title;

  /// Seek here on first load (milliseconds)
  final int? startPositionMs;

  // Queue support (all optional)
  final List<String>? queue; // URLs
  final Map<String, String>? queueTitles; // url -> title
  final int? startIndex; // index into `queue`

  // NOTE: do NOT make this constructor const. We rely on runtime asserts.
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
  }) : assert(
         file != null || url != null || ((queue ?? const []).isNotEmpty),
         'Provide a file, a url, or a non-empty queue',
       );

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // Local player
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

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

  // Network resiliency
  StreamSubscription<dynamic>? _connSub;
  bool _lostNetwork = false;

  // Track progress to return on pop
  int _lastPosMs = 0;
  int _lastDurMs = 0;
  bool _popped = false;

  // Track buffering/playing to control overlay
  bool _wasBuffering = false;
  bool _wasPlaying = false;

  // Chromecast
  StreamSubscription<GoogleCastSession?>? _gcSessionSub;
  StreamSubscription? _gcMediaStatusSub;
  bool _isCastingChromecast = false;

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
    _initNetworkHandlers();
    _initChromecast();
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
      // local file-only mode — no URLs
      _urls = const [];
      _titles = const {};
      _queueIndex = 0;
    }
  }

  @override
  void dispose() {
    _disposePlayers();

    // Network
    _connSub?.cancel();
    WakelockPlus.disable();

    // Chromecast cleanup
    _gcSessionSub?.cancel();
    _gcMediaStatusSub?.cancel();
    try {
      GoogleCastSessionManager.instance.endSessionAndStopCasting();
      GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (_) {}

    // DLNA cleanup
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

  // ───────────────────── Network handling ─────────────────────
  void _initNetworkHandlers() {
    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      bool connected;
      if (event is ConnectivityResult) {
        connected = event != ConnectivityResult.none;
      } else {
        connected = event.any((r) => r != ConnectivityResult.none);
      }

      if (!connected && !_lostNetwork) {
        _lostNetwork = true;
        if (_videoController?.value.isPlaying == true) {
          await _videoController!.pause();
        }
        if (mounted) setState(() {});
      } else if (connected && _lostNetwork) {
        _lostNetwork = false;
        if (mounted) setState(() {}); // Force rebuild

        // Resume playback if it was playing
        if (_chewieController != null &&
            !_chewieController!.videoPlayerController.value.isPlaying) {
          await _chewieController!.play();
        }
      }
    });
  }

  // ───────────────────── CAST: Chromecast ─────────────────────
  Future<void> _initChromecast() async {
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

      // Start discovery early, keep it alive
      try {
        await GoogleCastDiscoveryManager.instance.startDiscovery();
      } catch (_) {}

      // Observe session + media status
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
      debugPrint('Chromecast init error: $e');
    }
  }

  Future<void> _castToChromecast() async {
    if (!_hasHttpUrl) return;
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
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        info,
        autoPlay: true,
        playPosition: _videoController?.value.position ?? Duration.zero,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Chromecast failed: $e')));
    }
  }

  // ───────────────────── CAST: DLNA ─────────────────────
  Future<void> _initDlna() async {
    if (!Platform.isAndroid) return; // plugin is Android-only
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

      // initial devices
      _dlnaDevices = await _dlna.getDiscoveredDevices();
      if (mounted) setState(() {});

      // keep short refresher polling then stop
      _dlnaRefreshTimer?.cancel();
      _dlnaRefreshTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        final list = await _dlna.getDiscoveredDevices();
        if (mounted) {
          setState(() => _dlnaDevices = list);
        }
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
    if (!_hasHttpUrl) return;
    final url = _currentUrl;
    final udn = device.udn;
    final meta = VideoMetadata(
      title: _currentTitle,
      upnpClass: 'object.item.videoItem',
      resolution: null,
      duration: null,
      genre: null,
    );
    try {
      if (_videoController?.value.isPlaying == true) {
        await _videoController!.pause();
      }
      await _dlna.setMediaUri(udn, Url(value: url), meta);
      await _dlna.play(udn);
      setState(() {
        _isCastingDlna = true;
        _activeDlnaUdn = udn;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('DLNA cast failed: $e')));
    }
  }

  Future<void> _stopDlnaPlayback() async {
    if (_activeDlnaUdn == null) return;
    try {
      await _dlna.stop(_activeDlnaUdn!);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isCastingDlna = false;
        _activeDlnaUdn = null;
      });
    }
  }

  // ───────────────────── Local Player (with queue) ─────────────────────
  Future<void> _initializePlayerForCurrent({bool initial = false}) async {
    _disposePlayers();

    // Pick source: local file when provided & no queue URL available; otherwise current URL
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

    // Make sure isBuffering transitions clear reliably
    await _videoController!.setLooping(false);

    // Seek to resume point only on very first load if provided
    if (initial &&
        widget.startPositionMs != null &&
        widget.startPositionMs! > 0) {
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
    final v = _videoController!.value;
    _lastPosMs = v.position.inMilliseconds;
    _lastDurMs = v.duration.inMilliseconds;

    // Detect "ended" and advance if we have more in the queue
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

    // Rebuild only when buffering/playing flips to avoid excessive setState.
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

  // ───────────────────── UI ─────────────────────
  @override
  Widget build(BuildContext context) {
    final isInitialized =
        _chewieController?.videoPlayerController.value.isInitialized ?? false;
    final isCasting = _isCastingChromecast || _isCastingDlna;
    final showBuffering =
        isInitialized &&
        !isCasting &&
        (_videoController?.value.isBuffering ?? false) &&
        !(_videoController?.value.isPlaying ?? false);

    final hasQueue = _urls.length > 1;

    return WillPopScope(
      onWillPop: _handlePopWithProgress,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_currentTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handlePopWithProgress(),
          ),
          actions: [
            if (hasQueue)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${_queueIndex + 1}/${_urls.length}'),
                ),
              ),
            IconButton(
              tooltip: 'Cast',
              icon: Icon(isCasting ? Icons.cast_connected : Icons.cast),
              onPressed: !_hasHttpUrl ? null : _openCastPicker,
            ),
            if (_isCastingDlna)
              IconButton(
                tooltip: 'Stop DLNA',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: _stopDlnaPlayback,
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
            // Main player
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

            // Chromecast mini controller
            const Align(
              alignment: Alignment.bottomCenter,
              child: GoogleCastMiniController(),
            ),

            // Buffering spinner (only when truly buffering)
            if (showBuffering) const Center(child: CircularProgressIndicator()),

            // Network lost banner
            if (_lostNetwork)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Connection lost. Reconnecting…',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        // Optional manual prev/next controls (uncomment if you want visible buttons)
        // floatingActionButton: hasQueue
        //     ? Row(
        //         mainAxisSize: MainAxisSize.min,
        //         children: [
        //           FloatingActionButton.small(
        //             onPressed: _playPrevInQueue,
        //             child: const Icon(Icons.skip_previous),
        //           ),
        //           const SizedBox(width: 12),
        //           FloatingActionButton.small(
        //             onPressed: _playNextInQueue,
        //             child: const Icon(Icons.skip_next),
        //           ),
        //         ],
        //       )
        //     : null,
      ),
    );
  }

  Future<bool> _handlePopWithProgress() async {
    if (_popped) return false;
    _popped = true;
    if (!mounted) return false;
    Navigator.of(
      context,
    ).pop(<String, int>{'positionMs': _lastPosMs, 'durationMs': _lastDurMs});
    return false; // handled
  }

  // Combined picker (Chromecast + DLNA)
  Future<void> _openCastPicker() async {
    // ensure discoveries are running/fresh
    try {
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (_) {}
    if (_dlnaReady) _startDlnaDiscovery();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
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

                // Chromecast
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
                                  SnackBar(content: Text('Connect failed: $e')),
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

                // DLNA
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
                            child: Text('DLNA not available on this platform'),
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
        );
      },
    );
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
