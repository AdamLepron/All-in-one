import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'video_project.dart';

/// Opens the player of one clip; null when it cannot be previewed.
typedef PreviewOpener = Future<VideoPlayerController?> Function(VideoClip clip);

/// The device's video player for a clip, or null when it will not open.
Future<VideoPlayerController?> openPreview(VideoClip clip) async {
  VideoPlayerController? controller;
  try {
    controller = clip.media.uri.startsWith('content:')
        ? VideoPlayerController.contentUri(
            Uri.parse(clip.media.uri),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
        : VideoPlayerController.file(
            File(clip.media.path),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
    // A file the player cannot open must not leave the preview waiting.
    await controller.initialize().timeout(const Duration(seconds: 10));
    return controller;
  } on Object {
    try {
      await controller?.dispose();
    } on Object {
      // Releasing a player that never opened can fail; nothing to do.
    }
    return null;
  }
}

/// Plays the whole montage as one continuous timeline: a single clock drives
/// which clip shows, the video player follows it, and the music and sounds
/// start and stop at their moments.
class TimelinePlayer extends ChangeNotifier {
  TimelinePlayer(
    this.project, {
    PreviewOpener? opener,
    this.sounds = true,
    this.tick = const Duration(milliseconds: 33),
    int Function()? clockMs,
  }) : _opener = opener ?? openPreview {
    final sw = Stopwatch()..start();
    _now = clockMs ?? (() => sw.elapsedMilliseconds);
  }

  final VideoProject project;
  final PreviewOpener _opener;

  /// Whether music and sounds are played in the preview.
  final bool sounds;
  final Duration tick;

  /// The playhead, in milliseconds of the finished video.
  final ValueNotifier<int> time = ValueNotifier(0);

  VideoPlayerController? _controller;
  String? _controllerUri;

  /// File of the clip the player is set up for (even when it is a picture).
  String? _activeUri;
  int _clipIndex = 0;
  bool _playing = false;
  bool _failed = false;
  bool _loading = false;
  int _generation = 0;
  Timer? _timer;
  late final int Function() _now;
  int _startedAt = 0;
  int _base = 0;
  bool _disposed = false;

  /// The player showing the current clip, once it is ready.
  VideoPlayerController? get controller => _controller;
  bool get playing => _playing;

  /// True when the current clip cannot be previewed (it still edits fine).
  bool get failed => _failed;
  bool get loading => _loading;
  int get clipIndex => _clipIndex;

  int get _total => project.totalMs;

  // ---- Moving and playing ----

  /// Opens the first clip; call once after creating the player.
  Future<void> start() => _follow(force: true);

  /// Puts the playhead at [ms] (clamped to the montage).
  Future<void> seek(int ms) async {
    time.value = ms.clamp(0, _total);
    if (_playing) {
      _base = time.value;
      _startedAt = _now();
    }
    await _follow(force: true);
  }

  Future<void> play() async {
    if (_playing) return;
    if (time.value >= _total) time.value = 0;
    _playing = true;
    _base = time.value;
    _startedAt = _now();
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _onTick());
    await _follow(force: true);
    unawaited(_controller?.play());
    _syncSounds();
    _notify();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_controller?.pause());
    _syncSounds();
    _notify();
  }

  void toggle() => _playing ? pause() : unawaited(play());

  /// Call after the montage was edited: keeps the playhead and the player
  /// consistent with the new clips.
  Future<void> projectChanged() async {
    time.value = time.value.clamp(0, _total);
    if (_playing) {
      _base = time.value;
      _startedAt = _now();
    }
    await _follow(force: true);
    _syncSounds();
  }

  /// One step of the clock (the timer calls it; tests call it directly).
  @visibleForTesting
  void debugTick() => _onTick();

  void _onTick() {
    if (!_playing || _disposed) return;
    final t = _base + (_now() - _startedAt);
    if (t >= _total) {
      time.value = _total;
      pause();
      return;
    }
    time.value = t;
    unawaited(_follow());
    _syncSounds();
  }

  // ---- Following the clock with the video player ----

  Future<void> _follow({bool force = false}) async {
    if (project.clips.isEmpty) return;
    final (index, offset) = project.locate(time.value);
    final clip = project.clips[index];
    final uri = clip.media.uri;
    if (_activeUri != uri) {
      _clipIndex = index;
      await _activate(index, offset);
      return;
    }
    _clipIndex = index;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = clip.startMs + (offset * clip.speed).round();
    final drift = (c.value.position.inMilliseconds - target).abs();
    // While playing, a small drift is normal; scrubbing always repositions.
    if (force || drift > 350) {
      unawaited(c.seekTo(Duration(milliseconds: target)));
    }
    _applyLevels(c, clip);
  }

  void _applyLevels(VideoPlayerController c, VideoClip clip) {
    final silent = project.muteOriginal || project.musicPath != null;
    c.setVolume(silent ? 0 : clip.volume.clamp(0.0, 1.0));
    final speed = clip.speed.clamp(minSpeed, maxSpeed);
    if (c.value.playbackSpeed != speed) c.setPlaybackSpeed(speed);
  }

  Future<void> _activate(int index, int offset) async {
    final generation = ++_generation;
    final clip = project.clips[index];
    _activeUri = clip.media.uri;
    final sameFile = _controller != null && _controllerUri == clip.media.uri;
    if (sameFile) {
      // The other half of a cut: same file, only the position changes.
      final c = _controller!;
      final target = clip.startMs + (offset * clip.speed).round();
      await c.seekTo(Duration(milliseconds: target));
      _applyLevels(c, clip);
      if (_playing) unawaited(c.play());
      return;
    }
    final old = _controller;
    _controller = null;
    _controllerUri = null;
    _failed = false;
    _loading = !clip.isImage;
    _notify();
    try {
      await old?.dispose();
    } on Object {
      // Already released.
    }
    if (clip.isImage) {
      _loading = false;
      _notify();
      return;
    }
    final c = await _opener(clip);
    if (_disposed || generation != _generation) {
      await c?.dispose();
      return;
    }
    _loading = false;
    if (c == null) {
      _failed = true;
      _notify();
      return;
    }
    clip.shownSize ??= c.value.size;
    await c.setLooping(false);
    _applyLevels(c, clip);
    await c.seekTo(
      Duration(milliseconds: clip.startMs + (offset * clip.speed).round()),
    );
    if (_disposed || generation != _generation) {
      await c.dispose();
      return;
    }
    _controller = c;
    _controllerUri = clip.media.uri;
    if (_playing) unawaited(c.play());
    _notify();
  }

  // ---- Music and sounds ----

  final Map<Object, _Voice> _voices = {};

  void _syncSounds() {
    if (!sounds || _disposed) return;
    final t = time.value;
    final live = <Object>{};
    void voice(
      Object key,
      String path,
      int startMs,
      int trimMs,
      double volume,
      bool loop,
      bool inRange,
    ) {
      live.add(key);
      final v = _voices.putIfAbsent(key, () => _Voice(AudioPlayer()));
      final want = _playing && inRange;
      v.volume = volume.clamp(0.0, 1.0);
      if (v.on) unawaited(v.player.setVolume(v.volume));
      if (want && !v.on) {
        v.on = true;
        unawaited(() async {
          try {
            if (v.path != path) {
              await v.player.setFilePath(path);
              v.path = path;
            }
            await v.player.setLoopMode(loop ? LoopMode.all : LoopMode.off);
            await v.player.setVolume(v.volume);
            await v.player.seek(Duration(milliseconds: trimMs + (t - startMs)));
            if (v.on) unawaited(v.player.play());
          } on Object {
            v.on = false;
          }
        }());
      } else if (!want && v.on) {
        v.on = false;
        unawaited(v.player.pause());
      }
    }

    if (project.musicPath != null) {
      voice('music', project.musicPath!, 0, 0, project.musicVolume, true, true);
    }
    for (final a in project.sounds) {
      voice(
        a,
        a.path,
        a.startMs,
        a.trimStartMs,
        a.volume,
        false,
        t >= a.startMs && t < a.endMs,
      );
    }
    // Sounds that were removed stop and go.
    for (final key in _voices.keys.where((k) => !live.contains(k)).toList()) {
      final v = _voices.remove(key)!;
      unawaited(v.player.dispose());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    final c = _controller;
    _controller = null;
    unawaited(c?.dispose());
    for (final v in _voices.values) {
      unawaited(v.player.dispose());
    }
    _voices.clear();
    time.dispose();
    super.dispose();
  }
}

class _Voice {
  _Voice(this.player);
  final AudioPlayer player;
  String? path;
  bool on = false;
  double volume = 1;
}
