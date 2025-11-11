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
  final String? url;
  final String identifier;
  final String title;

  /// If provided, the player seeks here after init (milliseconds).
  final int? startPositionMs;

  const VideoPlayerScreen({
    super.key,
    this.file,
    this.url,
    required this.identifier,
    required this.title,
    this.startPositionMs,
  }) : assert(file != null || url != null);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // ───────── Local player ─────────
  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  bool get _hasHttpUrl =>
      widget.url != null && widget.url!.toLowerCase().startsWith('http');

  // Network resiliency
  StreamSubscription<dynamic>? _connSub;
  bool _lostNetwork = false;

  // Track progress to return on pop
  int _lastPosMs = 0;
  int _lastDurMs = 0;
  bool _popped = false;

  // Track buffering/playing to control our overlay
  bool _wasBuffering = false;
  bool _wasPlaying = false;

  // ───────── Chromecast (Google Cast) ─────────
  StreamSubscription<GoogleCastSession?>? _gcSessionSub;
  StreamSubscription? _gcMediaStatusSub;
  bool _isCastingChromecast = false;

  // ───────── DLNA/UPnP (Android only) ─────────
  final MediaCastDlnaApi _dlna = MediaCastDlnaApi();
  List<DlnaDevice> _dlnaDevices = [];
  bool _dlnaReady = false;
  bool _isCastingDlna = false;
  DeviceUdn? _activeDlnaUdn;
  Timer? _dlnaRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _initNetworkHandlers();
    _initChromecast();
    _initDlna();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    // Local player
    _chewieController?.dispose();
    _videoController.removeListener(_onTick);
    _videoController.dispose();

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

  // ───────────────────── Network handling ─────────────────────
  void _initNetworkHandlers() {
    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      bool connected;
      if (event is ConnectivityResult) {
        connected = event != ConnectivityResult.none;
      } else
        connected = event.any((r) => r != ConnectivityResult.none);

      if (!connected && !_lostNetwork) {
        _lostNetwork = true;
        if (_videoController.value.isPlaying) await _videoController.pause();
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
          .listen((session) {
            if (session != null) {
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
    final url = widget.url!;
    final info = GoogleCastMediaInformation(
      contentId: url,
      contentUrl: Uri.parse(url),
      contentType: _guessMime(url),
      streamType: _guessStreamType(url),
      metadata: GoogleCastGenericMediaMetadata(
        title: widget.title,
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
      if (_videoController.value.isPlaying) {
        await _videoController.pause();
      }
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        info,
        autoPlay: true,
        playPosition: _videoController.value.position,
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
    final url = widget.url!;
    final udn = device.udn;
    final meta = VideoMetadata(
      title: widget.title,
      upnpClass: 'object.item.videoItem',
      resolution: null,
      duration: null,
      genre: null,
    );
    try {
      if (_videoController.value.isPlaying) {
        await _videoController.pause();
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

  // ───────────────────── Local Player ─────────────────────
  Future<void> _initializePlayer() async {
    if (widget.file != null) {
      _videoController = VideoPlayerController.file(widget.file!);
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url!),
        httpHeaders: Net.headers,
      );
    }

    _videoController.addListener(_onTick);
    await _videoController.initialize();

    // Force initial state
    _wasBuffering = _videoController.value.isBuffering;
    _wasPlaying = _videoController.value.isPlaying;

    // Ensure listener is attached
    _videoController.removeListener(_onTick);
    _videoController.addListener(_onTick);

    // Make sure isBuffering transitions clear reliably on some platforms
    await _videoController.setLooping(false);

    // Seek to resume point if provided
    final resumeMs = widget.startPositionMs ?? 0;
    if (resumeMs > 0) {
      await _videoController.seekTo(Duration(milliseconds: resumeMs));
    }

    // Initialize state for overlay control
    _wasBuffering = _videoController.value.isBuffering;
    _wasPlaying = _videoController.value.isPlaying;

    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      showControls: true,
    );
    if (mounted) setState(() {});
  }

  void _onTick() {
    final v = _videoController.value;
    _lastPosMs = v.position.inMilliseconds;
    _lastDurMs = v.duration.inMilliseconds;

    // Rebuild only when buffering/playing flips to avoid excessive setState.
    if (_wasBuffering != v.isBuffering || _wasPlaying != v.isPlaying) {
      setState(() {
        _wasBuffering = v.isBuffering;
        _wasPlaying = v.isPlaying;
      });
    }
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
        _videoController.value.isBuffering &&
        !_videoController.value.isPlaying;

    return WillPopScope(
      onWillPop: _handlePopWithProgress,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handlePopWithProgress(),
          ),
          actions: [
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
                  widget.url ?? widget.file?.path ?? widget.identifier,
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
    return false; // we've handled the pop
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
      useRootNavigator: true, // ← isolate from nested/tab navigators
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

                // Chromecast section
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
                        separatorBuilder: (_, _) => const Divider(height: 1),
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

                // DLNA section
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
                                    (_, _) => const Divider(height: 1),
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
