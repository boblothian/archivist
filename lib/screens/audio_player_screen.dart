// lib/screens/audio_player_screen.dart
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ArchiveAudioPlayerScreen extends StatefulWidget {
  final String url;
  final String? title;

  /// If provided, the player will seek here after load.
  final int? startPositionMs;

  const ArchiveAudioPlayerScreen({
    super.key,
    required this.url,
    this.title,
    this.startPositionMs,
  });

  @override
  State<ArchiveAudioPlayerScreen> createState() =>
      _ArchiveAudioPlayerScreenState();
}

class _ArchiveAudioPlayerScreenState extends State<ArchiveAudioPlayerScreen> {
  final _player = AudioPlayer();
  bool _lostNetwork = false;

  // Cancel on dispose
  StreamSubscription<dynamic>? _connSub;

  // Track progress to return on pop
  int _lastPosMs = 0;
  int _lastDurMs = 0;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    WakelockPlus.enable();

    // Track position/duration
    _player.positionStream.listen((pos) => _lastPosMs = pos.inMilliseconds);
    _player.durationStream.listen(
      (dur) => _lastDurMs = (dur ?? Duration.zero).inMilliseconds,
    );

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setUrl(widget.url);

    // Resume if requested
    final resumeMs = widget.startPositionMs ?? 0;
    if (resumeMs > 0) {
      await _player.seek(Duration(milliseconds: resumeMs));
    }

    _player.play();

    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      bool connected;
      if (event is ConnectivityResult) {
        connected = event != ConnectivityResult.none;
      } else if (event is List<ConnectivityResult>) {
        connected = event.any((r) => r != ConnectivityResult.none);
      } else {
        connected = true;
      }

      if (!connected) {
        _lostNetwork = true;
        if (_player.playing) await _player.pause();
        if (mounted) setState(() {});
      } else if (_lostNetwork) {
        _lostNetwork = false;
        final pos = await _player.position;
        await _player.seek(pos);
        await _player.play();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
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
    return false; // we've handled the pop
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handlePopWithProgress,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'Audio'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async => _handlePopWithProgress(),
          ),
        ),
        body: StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_lostNetwork)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Connection lost. Reconnecting…'),
                  ),
                StreamBuilder<Duration?>(
                  stream: _player.durationStream,
                  builder: (c, dSnap) {
                    final total = dSnap.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (c, pSnap) {
                        final pos = pSnap.data ?? Duration.zero;
                        return Column(
                          children: [
                            Slider(
                              value: pos.inMilliseconds.toDouble().clamp(
                                0,
                                total.inMilliseconds.toDouble(),
                              ),
                              max:
                                  total.inMilliseconds.toDouble() == 0
                                      ? 1
                                      : total.inMilliseconds.toDouble(),
                              onChanged:
                                  (v) => _player.seek(
                                    Duration(milliseconds: v.toInt()),
                                  ),
                            ),
                            Text('${_fmt(pos)} / ${_fmt(total)}'),
                          ],
                        );
                      },
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      onPressed:
                          () => _player.seek(
                            (_player.position - const Duration(seconds: 10))
                                .clamp(
                                  Duration.zero,
                                  _player.duration ?? Duration.zero,
                                ),
                          ),
                    ),
                    IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed:
                          () => playing ? _player.pause() : _player.play(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      onPressed:
                          () => _player.seek(
                            _player.position + const Duration(seconds: 10),
                          ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }
}

extension _Clamp on Duration {
  Duration clamp(Duration min, Duration max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }
}
