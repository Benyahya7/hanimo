// Player: plain video_player for Animeify's direct mp4 links.
// Tap = show/hide controls (auto-hide after 4s), double-tap = +/-10s,
// speed 0.5–2.0x, fullscreen landscape, resume position saved locally.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/presentation/app_state.dart';

class PlayerPage extends StatefulWidget {
  final Anime anime;
  final int episodeNumber;
  final String videoUrl;
  const PlayerPage({super.key, required this.anime, required this.episodeNumber, required this.videoUrl});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _showControls = true;
  Timer? _hideTimer;
  String? _error;
  double _speed = 1.0;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (!mounted) return;
      final saved = context.read<AppState>().progress[widget.anime.id] ?? 0;
      if (saved > 0 && saved < 1) {
        final pos = Duration(milliseconds: (_controller.value.duration.inMilliseconds * saved).round());
        _controller.seekTo(pos);
      }
      _controller.play();
      _controller.addListener(_onProgress);
      setState(() => _ready = true);
      _scheduleHide();
    }).catchError((e) {
      if (mounted) setState(() => _error = 'Could not play this video: $e');
    });
  }

  void _onProgress() {
    final v = _controller.value;
    if (v.duration.inMilliseconds > 0) {
      final frac = v.position.inMilliseconds / v.duration.inMilliseconds;
      context.read<AppState>().setProgress(widget.anime, frac);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) setState(() => _showControls = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onProgress);
    _controller.dispose();
    if (_fullscreen) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  void _seekBy(int seconds) {
    final v = _controller.value;
    final target = v.position + Duration(seconds: seconds);
    _controller.seekTo(target < Duration.zero ? Duration.zero : (target > v.duration ? v.duration : target));
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
                    ],
                  ),
                ),
              )
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : GestureDetector(
                    onTap: () {
                      setState(() => _showControls = !_showControls);
                      if (_showControls) _scheduleHide();
                    },
                    onDoubleTapDown: (details) {
                      final w = MediaQuery.of(context).size.width;
                      _seekBy(details.globalPosition.dx < w / 2 ? -10 : 10);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
                        if (_controller.value.isBuffering) const CircularProgressIndicator(color: Colors.white),
                        if (_showControls)
                          Container(
                            color: Colors.black45,
                            child: Column(
                              children: [
                                AppBar(
                                  backgroundColor: Colors.transparent,
                                  title: Text('${widget.anime.title} — Ep ${widget.episodeNumber}'),
                                ),
                                const Spacer(),
                                IconButton(
                                  iconSize: 64,
                                  icon: Icon(_controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                                  onPressed: () {
                                    setState(() {
                                      _controller.value.isPlaying ? _controller.pause() : _controller.play();
                                    });
                                    _scheduleHide();
                                  },
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Text(_fmt(_controller.value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                      Expanded(
                                        child: Slider(
                                          value: _controller.value.position.inMilliseconds.toDouble(),
                                          max: _controller.value.duration.inMilliseconds.toDouble(),
                                          onChanged: (v) => _controller.seekTo(Duration(milliseconds: v.round())),
                                        ),
                                      ),
                                      Text(_fmt(_controller.value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                      PopupMenuButton<double>(
                                        icon: const Icon(Icons.speed, color: Colors.white),
                                        onSelected: (s) {
                                          setState(() => _speed = s);
                                          _controller.setPlaybackSpeed(s);
                                        },
                                        itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                            .map((s) => PopupMenuItem<double>(value: s, child: Text('${s}x${s == _speed ? ' ✓' : ''}')))
                                            .toList(),
                                      ),
                                      IconButton(
                                        icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                                        onPressed: _toggleFullscreen,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
