// lib/video_player_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart'; // NEW: DLNA
import 'package:video_player/video_player.dart';

import 'net.dart';

class VideoPlayerScreen extends StatefulWidget {
  final File? file;
  final String? url;
  final String identifier;
  final String title;

  const VideoPlayerScreen({
    super.key,
    this.file,
    this.url,
    required this.identifier,
    required this.title,
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

  // ───────── Chromecast (Google Cast) ─────────
  StreamSubscription<GoogleCastSession?>? _gcSessionSub;
  StreamSubscription<GoggleCastMediaStatus?>?
  _gcMediaStatusSub; // (package name typo)
  bool _isCastingChromecast = false;

  // ───────── DLNA/UPnP (Android only) ─────────
  final MediaCastDlnaApi _dlna = MediaCastDlnaApi();
  List<DlnaDevice> _dlnaDevices = [];
  bool _dlnaReady = false;
  bool _isCastingDlna = false;
  DeviceUdn? _activeDlnaUdn;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _initChromecast();
    _initDlna();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();

    // Chromecast cleanup
    _gcSessionSub?.cancel();
    _gcMediaStatusSub?.cancel();
    try {
      GoogleCastSessionManager.instance.endSessionAndStopCasting();
      GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (_) {}

    // DLNA cleanup
    _stopDlnaDiscovery();

    super.dispose();
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

      await GoogleCastDiscoveryManager.instance.startDiscovery();

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
      streamType: CastMediaStreamType.buffered,
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
      // poll discovered devices a few times
      _dlnaDevices = await _dlna.getDiscoveredDevices();
      if (mounted) setState(() {});
      // keep a short refresher run
      Timer.periodic(const Duration(seconds: 3), (t) async {
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
      upnpClass: 'object.item.videoItem', // generic class
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
    await _videoController.initialize();
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

  // ───────────────────── UI ─────────────────────
  @override
  Widget build(BuildContext context) {
    final ready =
        _chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized;

    final isCasting = _isCastingChromecast || _isCastingDlna;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                await GoogleCastSessionManager.instance
                    .endSessionAndStopCasting();
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          if (!ready)
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
            Chewie(controller: _chewieController!),

          // Mini controller for Chromecast (auto shows when casting)
          const Align(
            alignment: Alignment.bottomCenter,
            child: GoogleCastMiniController(),
          ),
        ],
      ),
    );
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
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final d = devices[i];
                          return ListTile(
                            leading: const Icon(Icons.cast),
                            title: Text(d.friendlyName ?? 'Chromecast'),
                            subtitle: Text(d.modelName ?? d.deviceID ?? ''),
                            onTap: () async {
                              try {
                                await GoogleCastSessionManager.instance
                                    .startSessionWithDevice(d);
                                if (context.mounted) Navigator.pop(context);
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
                                    (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final dev = _dlnaDevices[i];
                                  return ListTile(
                                    leading: const Icon(Icons.tv_outlined),
                                    title: Text(
                                      dev.friendlyName ?? 'DLNA device',
                                    ),
                                    subtitle: Text(dev.deviceType),
                                    onTap: () async {
                                      try {
                                        await _castToDlna(dev);
                                        if (context.mounted)
                                          Navigator.pop(context);
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
}
