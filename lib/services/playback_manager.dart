// lib/services/playback_manager.dart
import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class PlaybackManager with ChangeNotifier {
  PlaybackManager._();
  static final PlaybackManager instance = PlaybackManager._();

  VideoPlayerController? _video;
  ChewieController? _chewie;
  bool _keepAliveInBackground =
      false; // why: avoid disposing while AirPlay runs
  bool _initialized = false;

  VideoPlayerController? get video => _video;
  ChewieController? get chewie => _chewie;
  bool get isInitialized =>
      _chewie?.videoPlayerController.value.isInitialized ?? false;

  /// Call once at app start (see main.dart)
  static Future<void> configureAudioSessionOnce() async {
    if (!Platform.isIOS) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);
  }

  Future<void> initFromFile(String path, {Duration? seekTo}) async {
    await _initCore(
      VideoPlayerController.file(
        File(path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      ),
      seekTo: seekTo,
    );
  }

  Future<void> initFromUrl(
    Uri url, {
    Map<String, String>? headers,
    Duration? seekTo,
  }) async {
    await _initCore(
      VideoPlayerController.networkUrl(
        url,
        httpHeaders: headers ?? const {},
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      ),
      seekTo: seekTo,
    );
  }

  Future<void> _initCore(
    VideoPlayerController controller, {
    Duration? seekTo,
  }) async {
    if (_video != null && !_keepAliveInBackground) {
      await _disposeInternal();
    }
    _video = controller;
    await _video!.initialize();
    await _video!.setLooping(false);
    if (seekTo != null && seekTo > Duration.zero) {
      await _video!.seekTo(seekTo);
    }
    _chewie = ChewieController(
      videoPlayerController: _video!,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      showControls: true,
    );
    _initialized = true;
    notifyListeners();
  }

  void keepAliveInBackground(bool keep) {
    _keepAliveInBackground = keep;
  }

  Future<void> disposeIfAllowed() async {
    if (_keepAliveInBackground) return;
    await _disposeInternal();
  }

  Future<void> _disposeInternal() async {
    // Capture refs to avoid null-aware await issues
    final chewie = _chewie;
    final video = _video;

    _chewie = null;
    _video = null;
    _initialized = false;
    _keepAliveInBackground = false;

    // pause()/dispose() may be void or Future<void> depending on versions.
    // Future.sync handles both.
    try {
      if (chewie != null) {
        await Future.sync(() => chewie.pause());
      }
    } catch (_) {}

    if (chewie != null) {
      await Future.sync(() => chewie.dispose());
    }
    if (video != null) {
      await Future.sync(() => video.dispose());
    }

    notifyListeners();
  }
}
