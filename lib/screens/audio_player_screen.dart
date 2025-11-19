// lib/screens/audio_player_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:waveform_visualizer/waveform_visualizer.dart';

import '../net.dart';
import '../widgets/marquee_text.dart'; // for Net.headers

class ArchiveAudioPlayerScreen extends StatefulWidget {
  /// Single URL (used when there is no queue)
  final String url;

  /// Optional title shown in the AppBar (fallback to filename)
  final String? title;

  /// If provided, the player will seek here after load (ms)
  final int? startPositionMs;

  // ───────────────── Queue support ─────────────────
  /// Full playlist (if you want auto-next)
  final List<String>? queue;

  /// Optional url -> display title map
  final Map<String, String>? queueTitles;

  /// Optional url -> artwork/thumbnail map
  final Map<String, String>? queueThumbnails;

  /// Index in `queue` to start from
  final int? startIndex;

  const ArchiveAudioPlayerScreen({
    super.key,
    required this.url,
    this.title,
    this.startPositionMs,

    // queue
    this.queue,
    this.queueTitles,
    this.queueThumbnails,
    this.startIndex,
  });

  @override
  State<ArchiveAudioPlayerScreen> createState() =>
      _ArchiveAudioPlayerScreenState();
}

class _ArchiveAudioPlayerScreenState extends State<ArchiveAudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  final _player = AudioPlayer();

  // Connectivity
  StreamSubscription<dynamic>? _connSub;
  bool _lostNetwork = false;

  // Track progress to return on pop
  int _lastPosMs = 0;
  int _lastDurMs = 0;
  bool _popped = false;

  // Queue state
  List<String> _urls = const [];
  Map<String, String> _titles = const {};
  Map<String, String> _thumbs = const {};
  int _startIndex = 0;

  // Waveform + flip animation
  late final WaveformController _waveController;
  late final AnimationController _flipController;
  late final Animation<double> _flip;

  // Convenience
  String get _currentUrl {
    final idx = _player.currentIndex ?? _startIndex;
    return _urls[idx.clamp(0, _urls.length - 1)];
  }

  @override
  void initState() {
    super.initState();

    // ─────────── Waveform ───────────
    _waveController = WaveformController(
      maxDataPoints: 80,
      updateInterval: const Duration(milliseconds: 33),
      smoothingFactor: 0.85,
    );

    // ─────────── Flip animation ───────────
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _flip = Tween<double>(begin: 0.0, end: math.pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutCubic),
    );

    _initQueueState();
    _init();

    // Start/stop visualizer based on playback
    _player.playerStateStream.listen((st) {
      if (st.playing) {
        if (!_waveController.isActive) _waveController.start();
      } else {
        _waveController.stop();
      }
    });
  }

  void _initQueueState() {
    if (widget.queue != null && widget.queue!.isNotEmpty) {
      _urls = List<String>.from(widget.queue!);
      _titles = Map<String, String>.from(widget.queueTitles ?? const {});
      _thumbs = Map<String, String>.from(widget.queueThumbnails ?? const {});
      _startIndex = (widget.startIndex ?? 0).clamp(0, _urls.length - 1);
    } else {
      _urls = [widget.url];
      _titles = Map<String, String>.from(widget.queueTitles ?? const {});
      _thumbs = Map<String, String>.from(widget.queueThumbnails ?? const {});
      _startIndex = 0;
    }
  }

  Future<void> _init() async {
    WakelockPlus.enable();

    _player.positionStream.listen((pos) => _lastPosMs = pos.inMilliseconds);
    _player.durationStream.listen(
      (dur) => _lastDurMs = (dur ?? Duration.zero).inMilliseconds,
    );

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Build audio source (single or playlist)
    if (_urls.length == 1) {
      final u = _urls.first;
      final t = _titles[u] ?? widget.title ?? Uri.parse(u).pathSegments.last;
      final art = _thumbs[u];

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(u),
          headers: Net.headers,
          tag: MediaItem(
            id: u,
            title: t,
            artUri: (art != null && art.isNotEmpty) ? Uri.parse(art) : null,
          ),
        ),
        preload: true,
      );
    } else {
      final children = <AudioSource>[];
      for (final u in _urls) {
        final t = _titles[u] ?? widget.title ?? Uri.parse(u).pathSegments.last;
        final art = _thumbs[u];
        children.add(
          AudioSource.uri(
            Uri.parse(u),
            headers: Net.headers,
            tag: MediaItem(
              id: u,
              title: t,
              artUri: (art != null && art.isNotEmpty) ? Uri.parse(art) : null,
            ),
          ),
        );
      }
      final playlist = ConcatenatingAudioSource(children: children);
      await _player.setAudioSource(
        playlist,
        initialIndex: _startIndex,
        preload: true,
      );
    }

    if ((widget.startPositionMs ?? 0) > 0) {
      try {
        await _player.seek(
          Duration(milliseconds: widget.startPositionMs!),
          index: _player.currentIndex ?? _startIndex,
        );
      } catch (_) {}
    }

    await _player.play();

    // Network handling
    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      bool connected;
      if (event is ConnectivityResult) {
        connected = event != ConnectivityResult.none;
      } else {
        connected = event.any((r) => r != ConnectivityResult.none);
      }

      if (!connected) {
        _lostNetwork = true;
        if (_player.playing) await _player.pause();
        if (mounted) setState(() {});
      } else if (_lostNetwork) {
        _lostNetwork = false;
        final pos = _player.position;
        await _player.seek(pos, index: _player.currentIndex);
        await _player.play();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    if (!_popped) {
      _popped = true;
      Navigator.of(
        context,
      ).pop(<String, int>{'positionMs': _lastPosMs, 'durationMs': _lastDurMs});
    }
    _waveController.dispose();
    _flipController.dispose();
    _connSub?.cancel();
    WakelockPlus.disable();
    _player.dispose();
    super.dispose();
  }

  Future<bool> _handlePopWithProgress() async {
    if (_popped) return false;
    _popped = true;
    Navigator.of(
      context,
    ).pop(<String, int>{'positionMs': _lastPosMs, 'durationMs': _lastDurMs});
    return false;
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  void _flipCard() {
    if (_flipController.isDismissed) {
      _flipController.forward();
    } else if (_flipController.isCompleted) {
      _flipController.reverse();
    } else {
      _flipController.value < 0.5
          ? _flipController.forward()
          : _flipController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handlePopWithProgress,
      child: Scaffold(
        appBar: AppBar(
          title: StreamBuilder<SequenceState?>(
            stream: _player.sequenceStateStream,
            builder: (context, s) {
              final st = s.data;
              final idx = st?.currentIndex ?? _startIndex;
              final raw =
                  _titles[_urls[idx]] ??
                  widget.title ??
                  Uri.parse(_urls[idx]).pathSegments.last;
              return MarqueeText(
                text: raw,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              );
            },
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async => _handlePopWithProgress(),
          ),
        ),
        body: StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            final hasQueue = _urls.length > 1;

            return Column(
              children: [
                // ────────────────────── ARTWORK + FLIP ──────────────────────
                StreamBuilder<SequenceState?>(
                  stream: _player.sequenceStateStream,
                  builder: (context, s) {
                    final st = s.data;
                    final idx = st?.currentIndex ?? _startIndex;
                    final thumb = _thumbs[_urls[idx]];

                    if (thumb == null || thumb.isEmpty) {
                      return const SizedBox(height: 200);
                    }

                    return AspectRatio(
                      aspectRatio: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 12,
                          left: 12,
                          right: 12,
                        ),
                        child: GestureDetector(
                          onTap: _flipCard,
                          child: AnimatedBuilder(
                            animation: _flip,
                            builder: (context, _) {
                              final angle = _flip.value;
                              final front = angle <= math.pi / 2;
                              final display = front ? angle : angle - math.pi;

                              // FRONT (Tilt + Album)
                              Widget frontFace = Tilt(
                                fps: 90,
                                borderRadius: BorderRadius.circular(12),
                                tiltConfig: const TiltConfig(
                                  angle: 14,
                                  enableGestureSensors: false,
                                  enableGestureHover: false,
                                  enableGestureTouch: true,
                                  enableReverse: true,
                                  enableRevert: true,
                                  moveDuration: Duration(milliseconds: 90),
                                  moveCurve: Curves.easeOutCubic,
                                  leaveDuration: Duration(milliseconds: 220),
                                  leaveCurve: Curves.easeOutBack,
                                ),
                                lightConfig: const LightConfig(
                                  disable: false,
                                  minIntensity: 0.05,
                                  maxIntensity: 0.35,
                                  spreadFactor: 3.0,
                                ),
                                shadowConfig: const ShadowConfig(
                                  disable: false,
                                  minIntensity: 0.1,
                                  maxIntensity: 0.5,
                                  offsetFactor: 0.18,
                                  minBlurRadius: 14.0,
                                  maxBlurRadius: 26.0,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    thumb,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (_, __, ___) => const Icon(
                                          Icons.music_note,
                                          size: 48,
                                        ),
                                  ),
                                ),
                              );

                              // BACK (Waveform Visualizer)
                              Widget backFace = ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  color: Colors.black,
                                  child: LayoutBuilder(
                                    builder:
                                        (_, c) => WaveformWidget(
                                          controller: _waveController,
                                          height: c.maxHeight,
                                          style: WaveformStyle(
                                            waveColor:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                            backgroundColor: Colors.black,
                                            waveformStyle:
                                                WaveformDrawStyle.bars,
                                            barCount: 60,
                                            barSpacing: 3.0,
                                            showGradient: true,
                                          ),
                                        ),
                                  ),
                                ),
                              );

                              return Transform(
                                alignment: Alignment.center,
                                transform:
                                    Matrix4.identity()
                                      ..setEntry(3, 2, 0.001)
                                      ..rotateY(display),
                                child: front ? frontFace : backFace,
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

                if (_lostNetwork)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Connection lost. Reconnecting…'),
                  ),

                // ────────────────────── POSITION + SLIDER ──────────────────────
                StreamBuilder<Duration?>(
                  stream: _player.durationStream,
                  builder: (c, dur) {
                    final total = dur.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (c, pos) {
                        final p = pos.data ?? Duration.zero;
                        final max = total.inMilliseconds.toDouble();
                        final v =
                            p.inMilliseconds.clamp(0, max.toInt()).toDouble();

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Slider(
                                value: max == 0 ? 0 : v,
                                max: max == 0 ? 1 : max,
                                onChanged:
                                    (val) => _player.seek(
                                      Duration(milliseconds: val.toInt()),
                                      index: _player.currentIndex,
                                    ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('${_fmt(p)} / ${_fmt(total)}'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),

                // ────────────────────── CONTROLS ──────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Back 10s',
                      icon: const Icon(Icons.replay_10),
                      onPressed: () {
                        final tgt =
                            _player.position - const Duration(seconds: 10);
                        _player.seek(
                          tgt < Duration.zero ? Duration.zero : tgt,
                          index: _player.currentIndex,
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed:
                          () => playing ? _player.pause() : _player.play(),
                    ),
                    IconButton(
                      tooltip: 'Forward 10s',
                      icon: const Icon(Icons.forward_10),
                      onPressed: () {
                        final dur = _player.duration ?? Duration.zero;
                        final tgt =
                            _player.position + const Duration(seconds: 10);
                        _player.seek(
                          tgt > dur ? dur : tgt,
                          index: _player.currentIndex,
                        );
                      },
                    ),
                  ],
                ),

                // ────────────────────── QUEUE NAV ──────────────────────
                if (hasQueue)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: StreamBuilder<SequenceState?>(
                      stream: _player.sequenceStateStream,
                      builder: (context, st) {
                        final s = st.data;
                        final idx = s?.currentIndex ?? _startIndex;
                        return Text(
                          '${idx + 1} / ${_urls.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      },
                    ),
                  ),
                if (hasQueue)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () async {
                          try {
                            await _player.seekToPrevious();
                            await _player.play();
                          } catch (_) {}
                        },
                      ),
                      IconButton(
                        tooltip: 'Next',
                        icon: const Icon(Icons.skip_next),
                        onPressed: () async {
                          try {
                            await _player.seekToNext();
                            await _player.play();
                          } catch (_) {}
                        },
                      ),
                    ],
                  ),

                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}
