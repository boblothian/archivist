// lib/video_player_screen.dart
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'net.dart';
import 'services/jellyfin_service.dart';

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
  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

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

  void _saveToJellyfin() async {
    final svc = JellyfinService.instance;
    final cfg = await svc.loadConfig() ?? await svc.showConfigDialog(context);
    if (cfg == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Uploading to Jellyfin…')));

    try {
      await svc.addMovieFromUrl(
        url: Uri.parse(widget.url ?? ''),
        title: widget.title,
        httpHeaders: Net.headers,
        onProgress: (sent, total) {
          if (total != null && total > 0) {
            final pct = (sent / total * 100).toStringAsFixed(0);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Uploading… $pct%')));
          }
        },
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploaded to Jellyfin!')));
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
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
        ],
      ),
      body:
          playerReady
              ? Chewie(controller: _chewieController!)
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
