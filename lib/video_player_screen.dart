// lib/video_player_screen.dart

import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
// Use the umbrella import to keep API surface stable across versions
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:video_player/video_player.dart';

import 'net.dart';
import 'services/jellyfin_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  // Cast state
  List<GoogleCastDevice> _castDevices = [];
  bool _castInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _initCast();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      httpHeaders: Net.headers, // <-- required for archive.org
    );
    await _videoController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
    );
    if (mounted) setState(() {});
  }

  void _saveToJellyfin() async {
    final svc = JellyfinService.instance;
    final cfg = await svc.loadConfig() ?? await svc.showConfigDialog(context);
    if (cfg == null) return;

    int lastPct = -1;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Uploading to Jellyfin…')));

    try {
      await svc.addMovieFromUrl(
        url: Uri.parse(widget.videoUrl),
        title: widget.title,
        // If you know a year, pass it here: year: '2023',
        httpHeaders: Net.headers, // archive.org needs this
        onProgress: (sent, total) {
          if (total != null && total > 0) {
            final pct = ((sent / total) * 100).floor();
            if (pct != lastPct) {
              lastPct = pct;
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Uploading… $pct%')));
            }
          }
        },
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to Jellyfin. Scanning library…')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _initCast() async {
    // Keep runtime init simple and compatible with current flutter_chrome_cast (>=1.1.0)
    const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;

    try {
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
    } catch (e) {
      // On Android, manifest/provider-based init can also work; swallow init errors.
      debugPrint('Cast init warning: $e');
    }

    _castInitialized = true;
    if (mounted) setState(() {});
  }

  Future<void> _startDiscovery() async {
    if (!_castInitialized) await _initCast();

    GoogleCastDiscoveryManager.instance.startDiscovery();
    final sub = GoogleCastDiscoveryManager.instance.devicesStream.listen((
      devices,
    ) {
      if (!mounted) return;
      setState(() => _castDevices = devices);
    });

    await Future.delayed(const Duration(seconds: 3));
    await sub.cancel();
    GoogleCastDiscoveryManager.instance.stopDiscovery();

    if (_castDevices.isEmpty && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No Cast devices found')));
    }
  }

  Future<void> _connectAndCast(GoogleCastDevice device) async {
    try {
      await GoogleCastSessionManager.instance.startSessionWithDevice(device);

      // Build platform-appropriate metadata + media info to match native serializers.
      final CastMediaStreamType streamType = CastMediaStreamType.buffered;

      if (Platform.isAndroid) {
        final metadata = GoogleCastMovieMediaMetadataAndroid(
          title: widget.title,
          releaseDate: DateTime.now(),
          images: const [],
        );

        final mediaInfo = GoogleCastMediaInformationAndroid(
          // Use URL as contentId to keep receiver simple; also set contentUrl explicitly.
          contentId: widget.videoUrl,
          streamType: streamType,
          contentType: 'video/mp4',
          contentUrl: Uri.parse(widget.videoUrl),
          metadata: metadata,
        );

        // Load a single item to avoid queue serialization mismatches on some plugin versions.
        await GoogleCastRemoteMediaClient.instance.loadMedia(
          mediaInfo,
          autoPlay: true,
          playPosition: Duration.zero,
        );
      } else {
        final metadata = GoogleCastMovieMediaMetadata(
          title: widget.title,
          releaseDate: DateTime.now(),
          images: const [],
        );

        final mediaInfo = GoogleCastMediaInformationIOS(
          contentId: widget.videoUrl,
          streamType: CastMediaStreamType.buffered,
          contentUrl: Uri.parse(widget.videoUrl),
          contentType: 'video/mp4',
          metadata: metadata,
        );

        await GoogleCastRemoteMediaClient.instance.loadMedia(
          mediaInfo,
          autoPlay: true,
          playPosition: Duration.zero,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Casting to ${device.friendlyName}')),
      );
    } catch (e, stack) {
      // Most common runtime error seen: type 'bool' is not a subtype of type 'Map' from platform channel.
      // That indicates a plugin/native version skew. This call is wrapped to fail gracefully.
      debugPrint('Cast error: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to cast: $e')));
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    GoogleCastSessionManager.instance.endSessionAndStopCasting();
    super.dispose();
  }

  Future<void> _openDevicePicker() async {
    await _startDiscovery();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Cast to device'), dense: true),
              ..._castDevices.map(
                (d) => ListTile(
                  leading: const Icon(Icons.cast),
                  title: Text(d.friendlyName),
                  subtitle: Text(d.modelName ?? ''),
                  onTap: () {
                    Navigator.pop(ctx);
                    _connectAndCast(d);
                  },
                ),
              ),
              if (_castDevices.isEmpty)
                const ListTile(title: Text('No devices found')),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerReady =
        _chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Save to Jellyfin',
            icon: const Icon(Icons.cloud_upload),
            onPressed: _saveToJellyfin,
          ),
          StreamBuilder<GoogleCastSession?>(
            stream: GoogleCastSessionManager.instance.currentSessionStream,
            builder: (context, snapshot) {
              final isConnected =
                  GoogleCastSessionManager.instance.connectionState ==
                  GoogleCastConnectState.connected;

              return IconButton(
                // Always open device picker; if connected user can switch target manually.
                icon: Icon(isConnected ? Icons.cast_connected : Icons.cast),
                onPressed: _openDevicePicker,
                tooltip: isConnected ? 'Casting' : 'Cast',
              );
            },
          ),
        ],
      ),
      body:
          playerReady
              ? Stack(
                children: [
                  Chewie(controller: _chewieController!),
                  // Optional: mini controller overlays when casting
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: GoogleCastMiniController(),
                  ),
                ],
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
