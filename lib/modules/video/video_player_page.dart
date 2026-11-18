import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../core/util.dart';
import '../gallery/media_library.dart';
import '../music/music_controller.dart';
import '../music/song.dart';
import 'subtitles.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

/// What a drag on the video is currently adjusting.
enum _Drag { none, seek, brightness, volume }

/// Gesture-driven video player.
///
/// Tap shows the controls, double-tap a side skips 10 s, a horizontal drag
/// seeks, a vertical drag changes brightness (left half) or volume (right
/// half), and holding plays at double speed.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.media,
    this.playlist = const [],
    this.index = 0,
  });
  final Media media;

  /// Videos played one after the other, [index] being [media].
  final List<Media> playlist;
  final int index;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  /// Screens alive at once: moving to the next video briefly has two, and
  /// the shared window settings must outlive the first.
  static int _instances = 0;

  late final VideoPlayerController _video;
  late final AppSettings _settings;
  bool _ready = false;
  String? _error;

  bool _controls = true;
  Timer? _hideTimer;
  bool _locked = false;
  bool _fill = false;
  double _speed = 1;
  bool _boosting = false;
  bool _landscape = false;

  List<SubtitleFile> _subtitleFiles = const [];
  String? _subtitlePath;
  bool _advancing = false;

  bool get _hasNext => widget.index + 1 < widget.playlist.length;
  bool get _hasPrevious => widget.index > 0 && widget.playlist.isNotEmpty;

  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  Duration _seekFrom = Duration.zero;
  Duration _seekTo = Duration.zero;
  double _brightness = 0.5;
  double _volume = 0.5;
  double _levelFrom = 0;

  /// Skip feedback: -1 left, 1 right, 0 none.
  int _skipSide = 0;
  Timer? _skipTimer;

  @override
  void initState() {
    super.initState();
    _instances++;
    _settings = context.read<AppSettings>();
    context.read<MusicController>().pause();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    MediaChannel.keepScreenOn(true);
    MediaChannel.brightness().then((v) => _brightness = v);
    MediaChannel.volume().then((v) => _volume = v);
    _video = widget.media.uri.startsWith('content:')
        ? VideoPlayerController.contentUri(Uri.parse(widget.media.uri))
        : VideoPlayerController.file(File(widget.media.path));
    _init();
  }

  Future<void> _init() async {
    try {
      await _video.initialize();
      if (!mounted) return;
      final size = _video.value.size;
      _setLandscape(size.width > size.height);
      final resume = _settings.videoPosition(widget.media.key);
      // Too close to the end means it was finished: start over.
      if (resume > Duration.zero &&
          resume < _video.value.duration - const Duration(seconds: 5)) {
        await _video.seekTo(resume);
      }
      _video.addListener(_onTick);
      await _video.play();
      setState(() => _ready = true);
      unawaited(_findSubtitles());
      MediaChannel.armPip(
        true,
        width: size.width.round().clamp(1, 100000),
        height: size.height.round().clamp(1, 100000),
      );
      _scheduleHide();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Lecture impossible pour ce fichier');
      }
    }
  }

  bool _wasPlaying = false;
  void _onTick() {
    final v = _video.value;
    final ended = v.isCompleted;
    if (v.isPlaying != _wasPlaying || ended) {
      _wasPlaying = v.isPlaying;
      if (mounted) {
        setState(() {
          if (ended) _controls = true;
        });
      }
    }
    if (ended && _hasNext && !_advancing) {
      _advancing = true;
      _open(widget.index + 1);
    }
  }

  /// Replaces this screen by the video at [index] of the playlist.
  void _open(int index) {
    if (index < 0 || index >= widget.playlist.length) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(
          media: widget.playlist[index],
          playlist: widget.playlist,
          index: index,
        ),
      ),
    );
  }

  Future<void> _findSubtitles() async {
    final found = findSubtitles(widget.media.path);
    if (!mounted) return;
    setState(() => _subtitleFiles = found);
    // A subtitle file named like the video is shown right away.
    if (found.isNotEmpty) await _useSubtitles(found.first.path);
  }

  Future<void> _useSubtitles(String? path) async {
    try {
      if (path == null) {
        await _video.setClosedCaptionFile(null);
      } else {
        final text = await readSubtitleText(path);
        await _video.setClosedCaptionFile(
          Future.value(parseSubtitles(path, text)),
        );
      }
      if (mounted) setState(() => _subtitlePath = path);
    } on Object {
      if (mounted) {
        setState(() => _subtitlePath = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sous-titres illisibles')));
      }
    }
  }

  void _setLandscape(bool landscape) {
    _landscape = landscape;
    SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipTimer?.cancel();
    if (_ready) {
      final v = _video.value;
      final finished = v.position >= v.duration - const Duration(seconds: 5);
      _settings.setVideoPosition(
        widget.media.key,
        finished ? Duration.zero : v.position,
      );
    }
    _video.dispose();
    if (--_instances == 0) {
      MediaChannel.armPip(false);
      MediaChannel.keepScreenOn(false);
      MediaChannel.setBrightness(-1);
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _video.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    final v = _video.value;
    if (v.isCompleted) {
      _video.seekTo(Duration.zero);
      _video.play();
    } else {
      v.isPlaying ? _video.pause() : _video.play();
    }
    _scheduleHide();
  }

  void _skip(int seconds) {
    final v = _video.value;
    final target = v.position + Duration(seconds: seconds);
    _video.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > v.duration
          ? v.duration
          : target,
    );
    setState(() => _skipSide = seconds.sign);
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _skipSide = 0);
    });
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _video.setPlaybackSpeed(speed);
  }

  // ---- Drag gestures ----

  void _onPanStart(DragStartDetails d) {
    _dragStart = d.localPosition;
    _drag = _Drag.none;
  }

  void _onPanUpdate(DragUpdateDetails d, Size area) {
    final delta = d.localPosition - _dragStart;
    if (_drag == _Drag.none) {
      if (delta.distance < 12) return;
      // The first clear movement decides what the gesture controls.
      if (delta.dx.abs() > delta.dy.abs()) {
        _drag = _Drag.seek;
        _seekFrom = _seekTo = _video.value.position;
      } else if (_dragStart.dx < area.width / 2) {
        _drag = _Drag.brightness;
        _levelFrom = _brightness;
      } else {
        _drag = _Drag.volume;
        _levelFrom = _volume;
      }
    }
    switch (_drag) {
      case _Drag.seek:
        // A full-width swipe covers 90 s, or the whole video if shorter.
        final total = _video.value.duration;
        final span = total.inSeconds < 90 ? total.inSeconds : 90;
        final target =
            _seekFrom +
            Duration(
              milliseconds: (delta.dx / area.width * span * 1000).round(),
            );
        setState(
          () => _seekTo = target < Duration.zero
              ? Duration.zero
              : target > total
              ? total
              : target,
        );
      case _Drag.brightness:
        setState(
          () => _brightness = (_levelFrom - delta.dy / (area.height * 0.7))
              .clamp(0.01, 1.0),
        );
        MediaChannel.setBrightness(_brightness);
      case _Drag.volume:
        setState(
          () => _volume = (_levelFrom - delta.dy / (area.height * 0.7)).clamp(
            0.0,
            1.0,
          ),
        );
        MediaChannel.setVolume(_volume);
      case _Drag.none:
        break;
    }
  }

  void _onPanEnd() {
    if (_drag == _Drag.seek) _video.seekTo(_seekTo);
    setState(() => _drag = _Drag.none);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? _ErrorView(message: _error!)
          : !_ready
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : LayoutBuilder(
              builder: (context, box) {
                final area = box.biggest;
                // In the floating window there is no room for controls.
                final mini = area.width < 360 || area.height < 220;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onDoubleTapDown: _locked
                          ? null
                          : (d) => _dragStart = d.localPosition,
                      onDoubleTap: _locked
                          ? null
                          : () => _skip(
                              _dragStart.dx < area.width / 2 ? -10 : 10,
                            ),
                      onLongPressStart: _locked
                          ? null
                          : (_) {
                              setState(() => _boosting = true);
                              _video.setPlaybackSpeed(2);
                            },
                      onLongPressEnd: _locked
                          ? null
                          : (_) {
                              setState(() => _boosting = false);
                              _video.setPlaybackSpeed(_speed);
                            },
                      onPanStart: _locked ? null : _onPanStart,
                      onPanUpdate: _locked
                          ? null
                          : (d) => _onPanUpdate(d, area),
                      onPanEnd: _locked ? null : (_) => _onPanEnd(),
                      child: Center(
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: _fill ? BoxFit.cover : BoxFit.contain,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _video.value.size.width,
                              height: _video.value.size.height,
                              child: VideoPlayer(_video),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_subtitlePath != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: _controls && !mini ? 84 : 24,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _video,
                            builder: (_, v, _) => v.caption.text.isEmpty
                                ? const SizedBox.shrink()
                                : Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          v.caption.text,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: mini ? 11 : 17,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    if (_skipSide != 0)
                      Align(
                        alignment: _skipSide < 0
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: _Bubble(
                            icon: _skipSide < 0
                                ? Icons.fast_rewind_rounded
                                : Icons.fast_forward_rounded,
                            label: '10 s',
                          ),
                        ),
                      ),
                    if (_boosting)
                      const Align(
                        alignment: Alignment(0, -0.8),
                        child: _Bubble(
                          icon: Icons.fast_forward_rounded,
                          label: '2×',
                        ),
                      ),
                    if (_drag == _Drag.seek)
                      Center(
                        child: _Bubble(
                          label:
                              '${formatDuration(_seekTo)}  (${_seekTo >= _seekFrom ? '+' : '−'}${formatDuration((_seekTo - _seekFrom).abs())})',
                        ),
                      ),
                    if (_drag == _Drag.brightness)
                      Center(
                        child: _LevelBubble(
                          icon: Icons.brightness_6_rounded,
                          value: _brightness,
                        ),
                      ),
                    if (_drag == _Drag.volume)
                      Center(
                        child: _LevelBubble(
                          icon: _volume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          value: _volume,
                        ),
                      ),
                    if (_controls && _locked)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: IconButton.filledTonal(
                            tooltip: 'Déverrouiller',
                            icon: const Icon(Icons.lock_rounded),
                            onPressed: () => setState(() => _locked = false),
                          ),
                        ),
                      ),
                    if (_controls && !_locked && !mini)
                      ..._buildControls(context),
                  ],
                );
              },
            ),
    );
  }

  List<Widget> _buildControls(BuildContext context) {
    const white = Colors.white;
    final value = _video.value;
    return [
      // Top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back),
                    color: white,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.media.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickSpeed,
                    child: Text(
                      '${formatNumber(_speed)}×',
                      style: const TextStyle(
                        color: white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _fill ? 'Ajuster' : "Remplir l'écran",
                    icon: Icon(
                      _fill ? Icons.fit_screen_outlined : Icons.aspect_ratio,
                    ),
                    color: white,
                    onPressed: () => setState(() => _fill = !_fill),
                  ),
                  IconButton(
                    tooltip: 'Plus d\'options',
                    icon: const Icon(Icons.more_vert),
                    color: white,
                    onPressed: _showMore,
                  ),
                  IconButton(
                    tooltip: "Verrouiller l'écran",
                    icon: const Icon(Icons.lock_open_rounded),
                    color: white,
                    onPressed: () => setState(() => _locked = true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Centre transport buttons
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasPrevious)
              IconButton(
                tooltip: 'Vidéo précédente',
                iconSize: 36,
                icon: const Icon(Icons.skip_previous_rounded),
                color: white,
                onPressed: () => _open(widget.index - 1),
              ),
            IconButton(
              tooltip: 'Reculer de 10 secondes',
              iconSize: 40,
              icon: const Icon(Icons.replay_10_rounded),
              color: white,
              onPressed: () {
                _skip(-10);
                _scheduleHide();
              },
            ),
            const SizedBox(width: 28),
            Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _togglePlay,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    value.isCompleted
                        ? Icons.replay_rounded
                        : value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 52,
                    color: white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 28),
            IconButton(
              tooltip: 'Avancer de 10 secondes',
              iconSize: 40,
              icon: const Icon(Icons.forward_10_rounded),
              color: white,
              onPressed: () {
                _skip(10);
                _scheduleHide();
              },
            ),
            if (_hasNext)
              IconButton(
                tooltip: 'Vidéo suivante',
                iconSize: 36,
                icon: const Icon(Icons.skip_next_rounded),
                color: white,
                onPressed: () => _open(widget.index + 1),
              ),
          ],
        ),
      ),
      // Bottom bar
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 4, 4),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _video,
                builder: (_, v, _) {
                  final total = v.duration.inMilliseconds.toDouble();
                  final position = v.position.inMilliseconds.toDouble().clamp(
                    0.0,
                    total,
                  );
                  return Row(
                    children: [
                      Text(
                        formatDuration(v.position),
                        style: const TextStyle(color: white, fontSize: 12),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            activeTrackColor: white,
                            inactiveTrackColor: white.withValues(alpha: 0.3),
                            thumbColor: white,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            max: total <= 0 ? 1 : total,
                            value: total <= 0 ? 0 : position,
                            onChangeStart: (_) => _hideTimer?.cancel(),
                            onChanged: (ms) => _video.seekTo(
                              Duration(milliseconds: ms.round()),
                            ),
                            onChangeEnd: (_) => _scheduleHide(),
                          ),
                        ),
                      ),
                      Text(
                        formatDuration(v.duration),
                        style: const TextStyle(color: white, fontSize: 12),
                      ),
                      IconButton(
                        tooltip: 'Pivoter',
                        icon: const Icon(Icons.screen_rotation_rounded),
                        color: white,
                        onPressed: () => _setLandscape(!_landscape),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ];
  }

  void _showMore() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: const Text('Sous-titres'),
                subtitle: Text(
                  _subtitlePath == null ? 'Désactivés' : 'Activés',
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  _pickSubtitles();
                },
              ),
              ListTile(
                leading: const Icon(Icons.audiotrack_outlined),
                title: const Text('Piste audio'),
                onTap: () {
                  Navigator.pop(sheet);
                  _pickAudioTrack();
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_in_picture_alt_rounded),
                title: const Text("Image dans l'image"),
                onTap: () async {
                  Navigator.pop(sheet);
                  final size = _video.value.size;
                  final ok = await MediaChannel.enterPip(
                    width: size.width.round().clamp(1, 100000),
                    height: size.height.round().clamp(1, 100000),
                  );
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Non disponible sur cet appareil"),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.headphones_rounded),
                title: const Text('Écouter sans l\'image'),
                subtitle: const Text('Continue en arrière-plan, écran éteint'),
                onTap: () {
                  Navigator.pop(sheet);
                  _toBackground();
                },
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _scheduleHide());
  }

  /// Hands the sound over to the music player, which keeps playing with the
  /// screen off, and closes the video.
  void _toBackground() {
    final music = context.read<MusicController>();
    final at = _video.value.position;
    final m = widget.media;
    music
        .play(
          [
            Song(
              // Negative ids never collide with the media library.
              id: -(m.key.hashCode.abs() + 1),
              title: m.name,
              artist: 'Vidéo',
              album: m.album,
              albumId: -1,
              duration: _video.value.duration,
              uri: m.uri.startsWith('content:')
                  ? m.uri
                  : Uri.file(m.path).toString(),
              path: m.path,
            ),
          ],
          0,
          shuffled: false,
        )
        .then((_) => music.seek(at));
    Navigator.of(context).pop();
  }

  Future<void> _pickAudioTrack() async {
    List<VideoAudioTrack> tracks = const [];
    try {
      tracks = await _video.getAudioTracks();
    } on Object {
      // Not supported by this player: the list stays empty.
    }
    if (!mounted) return;
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Piste audio')),
              if (tracks.length < 2)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Cette vidéo n\'a qu\'une seule piste audio.'),
                ),
              if (tracks.length >= 2)
                for (final (i, t) in tracks.indexed)
                  ListTile(
                    title: Text(trackName(t, i)),
                    selected: t.isSelected,
                    trailing: t.isSelected ? const Icon(Icons.check) : null,
                    onTap: () {
                      Navigator.pop(sheet);
                      _video.selectAudioTrack(t.id);
                    },
                  ),
            ],
          ),
        ),
      ),
    );
    _scheduleHide();
  }

  Future<void> _pickSubtitles() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Sous-titres')),
              ListTile(
                title: const Text('Désactivés'),
                selected: _subtitlePath == null,
                onTap: () {
                  Navigator.pop(sheet);
                  _useSubtitles(null);
                },
              ),
              for (final f in _subtitleFiles)
                ListTile(
                  title: Text(f.label),
                  subtitle: Text(
                    f.path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: _subtitlePath == f.path,
                  onTap: () {
                    Navigator.pop(sheet);
                    _useSubtitles(f.path);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('Choisir un fichier .srt ou .vtt…'),
                onTap: () {
                  Navigator.pop(sheet);
                  _browseSubtitles();
                },
              ),
            ],
          ),
        ),
      ),
    );
    _scheduleHide();
  }

  Future<void> _browseSubtitles() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (path == null) return;
    if (!subtitleExtensions.contains(p.extension(path).toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choisissez un fichier .srt ou .vtt')),
        );
      }
      return;
    }
    await _useSubtitles(path);
  }

  void _pickSpeed() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vitesse de lecture',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _speeds)
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text('${formatNumber(s)}×'),
                      selected: s == _speed,
                      onSelected: (_) {
                        _setSpeed(s);
                        Navigator.pop(sheet);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _scheduleHide());
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBubble extends StatelessWidget {
  const _LevelBubble({required this.icon, required this.value});
  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(value * 100).round()}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            color: Colors.white,
            onPressed: () => Navigator.of(context).pop(),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white54,
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text(message, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Français", "Anglais · 5.1" … a readable name for an audio track.
String trackName(VideoAudioTrack t, int index) {
  final parts = <String>[
    if ((t.label ?? '').trim().isNotEmpty)
      t.label!.trim()
    else if ((t.language ?? '').isNotEmpty && t.language != 'und')
      t.language!.toUpperCase()
    else
      'Piste ${index + 1}',
    if (t.channelCount != null && t.channelCount! > 2)
      '${t.channelCount} canaux',
  ];
  return parts.join(' · ');
}
