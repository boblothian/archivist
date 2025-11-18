// lib/screens/audio_player_screen.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

class _ArchiveAudioPlayerScreenState extends State<ArchiveAudioPlayerScreen> {
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

  // Convenience getters
  String get _currentUrl {
    final index = _player.currentIndex ?? _startIndex;
    return _urls[index.clamp(0, _urls.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _initQueueState();
    _init();
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

    // Track position/duration
    _player.positionStream.listen((pos) => _lastPosMs = pos.inMilliseconds);
    _player.durationStream.listen(
      (dur) => _lastDurMs = (dur ?? Duration.zero).inMilliseconds,
    );

    // Configure audio session
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Build source (single or playlist) WITH MediaItem tags for lock-screen
    if (_urls.length == 1) {
      final u = _urls.first;
      final title =
          _titles[u] ?? widget.title ?? Uri.parse(u).pathSegments.last;
      final art = _thumbs[u];

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(u),
          headers: Net.headers,
          tag: MediaItem(
            id: u,
            title: title,
            artUri: (art != null && art.isNotEmpty) ? Uri.parse(art) : null,
          ),
        ),
        preload: true,
      );
    } else {
      final sources = <AudioSource>[];
      for (final u in _urls) {
        final title =
            _titles[u] ?? widget.title ?? Uri.parse(u).pathSegments.last;
        final art = _thumbs[u];

        sources.add(
          AudioSource.uri(
            Uri.parse(u),
            headers: Net.headers,
            tag: MediaItem(
              id: u,
              title: title,
              artUri: (art != null && art.isNotEmpty) ? Uri.parse(art) : null,
            ),
          ),
        );
      }

      final playlist = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(
        playlist,
        initialIndex: _startIndex,
        preload: true,
      );
    }

    // Resume if requested (only on initial item)
    final resumeMs = widget.startPositionMs ?? 0;
    if (resumeMs > 0) {
      try {
        await _player.seek(
          Duration(milliseconds: resumeMs),
          index: _player.currentIndex ?? _startIndex,
        );
      } catch (_) {}
    }

    // Auto-advance is handled by just_audio; we just start playing.
    await _player.play();

    // Network handling
    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      bool connected;
      if (event is ConnectivityResult) {
        connected = event != ConnectivityResult.none;
      } else {
        // iOS streams a list
        connected = event.any((r) => r != ConnectivityResult.none);
      }

      if (!connected) {
        _lostNetwork = true;
        if (_player.playing) await _player.pause();
        if (mounted) setState(() {});
      } else if (_lostNetwork) {
        _lostNetwork = false;
        // Re-seek current position and resume
        final pos = _player.position;
        await _player.seek(pos, index: _player.currentIndex);
        await _player.play();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // Fallback: if this screen is being disposed without having
    // gone through _handlePopWithProgress, still return the
    // last known position/duration to the caller.
    if (!_popped) {
      _popped = true;
      // fire-and-forget; we can't await in dispose
      Navigator.of(
        context,
      ).pop(<String, int>{'positionMs': _lastPosMs, 'durationMs': _lastDurMs});
    }

    _connSub?.cancel();
    WakelockPlus.disable();
    _player.dispose();
    super.dispose();
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

  // UI helpers
  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handlePopWithProgress,
      child: Scaffold(
        appBar: AppBar(
          // This makes the title scroll when it's too long
          title: StreamBuilder<SequenceState?>(
            stream: _player.sequenceStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final index = state?.currentIndex ?? _startIndex;
              final currentUrl = _urls[index.clamp(0, _urls.length - 1)];
              final rawTitle =
                  _titles[currentUrl] ??
                  widget.title ??
                  Uri.parse(currentUrl).pathSegments.last;

              // Use the exact same MarqueeText you already created!
              return MarqueeText(
                text: rawTitle,
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
                // ────────────────────── ARTWORK (updates on track change) ──────────────────────
                StreamBuilder<SequenceState?>(
                  stream: _player.sequenceStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final index = state?.currentIndex ?? _startIndex;
                    final currentUrl = _urls[index.clamp(0, _urls.length - 1)];
                    final thumb = _thumbs[currentUrl];

                    if (thumb != null && thumb.isNotEmpty) {
                      return AspectRatio(
                        aspectRatio: 1,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: 12,
                            left: 12,
                            right: 12,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => Container(
                                    color: Colors.black12,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.music_note,
                                      size: 48,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                if (_lostNetwork)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Connection lost. Reconnecting…'),
                  ),

                // ────────────────────── POSITION / SLIDER ──────────────────────
                StreamBuilder<Duration?>(
                  stream: _player.durationStream,
                  builder: (c, dSnap) {
                    final Duration total = dSnap.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (c, pSnap) {
                        final Duration pos = pSnap.data ?? Duration.zero;

                        final double maxMsRaw = total.inMilliseconds.toDouble();
                        final double maxMs = maxMsRaw == 0 ? 1.0 : maxMsRaw;
                        final double posMs = pos.inMilliseconds.toDouble();
                        final double valueMs =
                            posMs < 0 ? 0.0 : (posMs > maxMs ? maxMs : posMs);

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Slider(
                                value: valueMs,
                                max: maxMs,
                                onChanged:
                                    (v) => _player.seek(
                                      Duration(milliseconds: v.toInt()),
                                      index: _player.currentIndex,
                                    ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('${_fmt(pos)} / ${_fmt(total)}'),
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
                        final target =
                            _player.position - const Duration(seconds: 10);
                        _player.seek(
                          target < Duration.zero ? Duration.zero : target,
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
                        final d = _player.duration ?? Duration.zero;
                        final target =
                            _player.position + const Duration(seconds: 10);
                        _player.seek(
                          target > d ? d : target,
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
                      builder: (context, sSnap) {
                        final seq = sSnap.data;
                        final idx = seq?.currentIndex ?? _startIndex;
                        final total = _urls.length;
                        return Text(
                          '${idx + 1} / $total',
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
