import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/platform.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../gallery/media_grid.dart';
import '../gallery/media_library.dart';
import 'project_store.dart';
import 'timeline_player.dart';
import 'timeline_view.dart';
import 'video_project.dart';

part 'video_editor_panels.dart';

/// Runs an export and returns the file path. [onProgress] receives 0–100.
typedef VideoExporterFn = Future<String> Function(
  Map<String, Object?> args,
  void Function(int percent) onProgress,
);

/// Default exporter: native Media3 export, polled for progress.
Future<String> nativeExport(
  Map<String, Object?> args,
  void Function(int) onProgress,
) async {
  final done = Completer<void>();
  unawaited(() async {
    while (!done.isCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (done.isCompleted) break;
      final percent = await MediaChannel.exportProgress();
      if (percent >= 0) onProgress(percent);
    }
  }());
  try {
    return await MediaChannel.exportVideo(args);
  } finally {
    done.complete();
  }
}

const moviesDir = '$storageRoot/Movies/All-in-One';

/// The side panel that is open, if any.
enum _Panel {
  speed,
  volume,
  filters,
  adjust,
  effects,
  transition,
  format,
  audio,
  overlay,
  textStyle,
  sound,
  segment,
}

const _bg = Color(0xFF0E0E11);
const _surface = Color(0xFF18181D);

/// The video editor, laid out like CapCut in landscape: preview on top,
/// the timeline below with a fixed playhead, a toolbar that follows what is
/// selected on the left, and a side panel for the settings of a tool.
///
/// The source videos are never changed; the result is a new MP4.
class VideoEditorPage extends StatefulWidget {
  const VideoEditorPage({
    super.key,
    this.media,
    this.project,
    this.store,
    this.exporter = nativeExport,
    this.outputDir,
    this.opener,
    this.previewSounds = true,
  }) : assert(media != null || project != null);

  /// Video a new montage starts from.
  final Media? media;

  /// A saved montage to carry on with.
  final VideoProject? project;

  /// Where montages are saved as they change.
  final ProjectStore? store;
  final VideoExporterFn exporter;

  /// Where the result is saved; Movies/All-in-One when null.
  final String? outputDir;

  /// How clips are opened for the preview (tests replace it).
  final PreviewOpener? opener;

  /// Whether the preview plays the music and sounds.
  final bool previewSounds;

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  late final VideoProject _project =
      widget.project ?? VideoProject(widget.media!);
  late final ProjectStore _store = widget.store ?? ProjectStore();
  late final TimelinePlayer _player = TimelinePlayer(
    _project,
    opener: widget.opener,
    sounds: widget.previewSounds,
  );

  Selection _sel = Selection.none;
  _Panel? _panel;
  double _ppm = defaultPxPerMs;
  Timer? _saveTimer;
  bool _dirty = false;

  // Undo and redo keep whole snapshots of the montage.
  final List<String> _undo = [];
  final List<String> _redo = [];
  DateTime _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Set by continuous gestures (a slider, a drag): the next edit joins the
  /// previous undo step instead of starting a new one.
  bool _merge = false;

  // Panel state that is not part of the montage.
  int _cutFrom = -1;
  int _cutTo = -1;
  AudioRecorder? _recorder;
  int _voiceFrom = 0;
  final Stopwatch _voiceClock = Stopwatch();

  @override
  void initState() {
    super.initState();
    // Editing is done sideways, with the whole screen.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player.addListener(_changed);
    unawaited(_player.start());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) _saveQuietly();
    _player.removeListener(_changed);
    _player.dispose();
    _recorder?.dispose();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Rebuilds after a change that is not an edit of the montage.
  void _ui(VoidCallback change) => setState(change);

  // ---- Editing, undo and redo ----

  VideoClip? get _clip =>
      _sel.kind == SelKind.clip && _sel.index < _project.clips.length
      ? _project.clips[_sel.index]
      : null;

  /// The clip under the playhead.
  int get _clipAtPlayhead => _project.locate(_player.time.value).$1;

  int get _now => _player.time.value;

  /// Runs a change of the montage: recorded for undo (the steps of one
  /// gesture count as one), saved a moment later, and the preview is told.
  void _edit(VoidCallback change) {
    final now = DateTime.now();
    final joins =
        _merge &&
        now.difference(_lastEdit) < const Duration(milliseconds: 1500);
    _merge = false;
    if (!joins) {
      _undo.add(jsonEncode(_project.toJson()));
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    _lastEdit = now;
    setState(() {
      change();
      _dirty = true;
      _fixSelection();
    });
    unawaited(_player.projectChanged());
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveQuietly);
  }

  void _drag(VoidCallback change) {
    _merge = true;
    _edit(change);
  }

  /// A selection never points past the end of its list.
  void _fixSelection() {
    final n = switch (_sel.kind) {
      SelKind.clip => _project.clips.length,
      SelKind.overlay => _project.overlays.length,
      SelKind.text => _project.titles.length,
      SelKind.sound => _project.sounds.length,
      SelKind.music => _project.musicPath == null ? 0 : 1,
      SelKind.none => 1,
    };
    if (_sel.kind != SelKind.none && _sel.index >= n) {
      _sel = Selection.none;
      _panel = null;
    }
  }

  void _undoStep() => _restore(_undo, _redo);
  void _redoStep() => _restore(_redo, _undo);

  void _restore(List<String> from, List<String> to) {
    if (from.isEmpty) return;
    to.add(jsonEncode(_project.toJson()));
    final snap = from.removeLast();
    setState(() {
      _project.replaceWith(
        VideoProject.fromJson(jsonDecode(snap) as Map<String, dynamic>),
      );
      _sel = Selection.none;
      _panel = null;
      _dirty = true;
      _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);
    });
    unawaited(_player.projectChanged());
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveQuietly);
  }

  /// Saving the montage must never get in the way of editing or exporting.
  void _saveQuietly() {
    _store.save(_project).catchError((Object _) {});
  }

  void _select(Selection s) {
    setState(() {
      _sel = s;
      // A panel belongs to what it edits.
      if (s.isNone) _panel = null;
      if (_panel != null && !_panelFits(_panel!, s)) _panel = null;
    });
  }

  bool _panelFits(_Panel panel, Selection s) => switch (panel) {
    _Panel.speed ||
    _Panel.volume ||
    _Panel.filters ||
    _Panel.adjust ||
    _Panel.effects ||
    _Panel.transition ||
    _Panel.segment => s.kind == SelKind.clip,
    _Panel.format || _Panel.audio => true,
    _Panel.overlay => s.kind == SelKind.overlay,
    _Panel.textStyle => s.kind == SelKind.text,
    _Panel.sound => s.kind == SelKind.sound,
  };

  void _openPanel(_Panel panel) => setState(() {
    _panel = _panel == panel ? null : panel;
    _cutFrom = -1;
    _cutTo = -1;
  });

  /// A clip tool used with nothing selected applies to the clip under the
  /// playhead.
  void _clipTool(_Panel panel) {
    if (_clip == null) {
      _sel = Selection(SelKind.clip, _clipAtPlayhead);
    }
    _openPanel(panel);
  }

  // ---- Playback ----

  void _scrubStart() {
    if (_player.playing) _player.pause();
  }

  void _seek(int ms) {
    unawaited(_player.seek(ms));
  }

  // ---- Tools ----

  void _split() {
    final t = _now;
    switch (_sel.kind) {
      case SelKind.overlay:
        final o = _project.overlays[_sel.index];
        if (t - o.startMs < minClipMs || o.endMs - t < minClipMs) {
          _tooClose();
          return;
        }
        _edit(() {
          final second = o.copy()
            ..startMs = t
            ..durationMs = o.endMs - t
            ..trimStartMs = o.isImage ? 0 : o.trimStartMs + (t - o.startMs);
          o.durationMs = t - o.startMs;
          _project.overlays.insert(_sel.index + 1, second);
        });
      case SelKind.text:
        final x = _project.titles[_sel.index];
        if (t - x.startMs < 300 || x.endMs - t < 300) {
          _tooClose();
          return;
        }
        _edit(() {
          final second = x.copyWith()
            ..startMs = t
            ..endMs = x.endMs;
          x.endMs = t;
          _project.titles.insert(_sel.index + 1, second);
        });
      case SelKind.sound:
        final a = _project.sounds[_sel.index];
        if (t - a.startMs < minClipMs || a.endMs - t < minClipMs) {
          _tooClose();
          return;
        }
        _edit(() {
          final second = AudioClip(
            a.path,
            a.name,
            startMs: t,
            trimStartMs: a.trimStartMs + (t - a.startMs),
            durationMs: a.endMs - t,
            sourceMs: a.sourceMs,
            volume: a.volume,
          );
          a.durationMs = t - a.startMs;
          _project.sounds.insert(_sel.index + 1, second);
        });
      case SelKind.clip || SelKind.none:
        // With nothing selected, the clip under the playhead is cut.
        final (index, offset) = _project.locate(t);
        final c = _project.clips[index];
        if (offset * 1.0 < minClipMs / c.speed ||
            c.outputMs - offset < minClipMs / c.speed) {
          return _tooClose();
        }
        _edit(() {
          _project.splitAtTime(t);
          _sel = Selection(SelKind.clip, index);
        });
      case SelKind.music:
        break;
    }
  }

  void _tooClose() =>
      showMessage(context, 'Placez la tête de lecture plus loin des bords');

  void _delete() {
    switch (_sel.kind) {
      case SelKind.clip:
        if (_project.clips.length == 1) {
          showMessage(context, 'Il faut garder au moins un extrait');
          return;
        }
        _edit(() => _project.clips.removeAt(_sel.index));
      case SelKind.overlay:
        _edit(() => _project.overlays.removeAt(_sel.index));
      case SelKind.text:
        _edit(() => _project.titles.removeAt(_sel.index));
      case SelKind.sound:
        _edit(() => _project.sounds.removeAt(_sel.index));
      case SelKind.music:
        _edit(() {
          _project
            ..musicPath = null
            ..musicName = null;
        });
      case SelKind.none:
        return;
    }
    setState(() {
      _sel = Selection.none;
      _panel = null;
    });
  }

  void _duplicate() {
    switch (_sel.kind) {
      case SelKind.clip:
        _edit(() {
          _project.clips.insert(_sel.index + 1, _clip!.copy());
          _sel = Selection(SelKind.clip, _sel.index + 1);
        });
      case SelKind.overlay:
        final o = _project.overlays[_sel.index];
        _edit(() {
          _project.overlays.add(o.copy()..startMs = o.endMs);
          _sel = Selection(SelKind.overlay, _project.overlays.length - 1);
        });
      case SelKind.text:
        final x = _project.titles[_sel.index];
        _edit(() {
          final len = x.endMs - x.startMs;
          _project.titles.add(
            x.copyWith()
              ..startMs = x.endMs
              ..endMs = x.endMs + len,
          );
          _sel = Selection(SelKind.text, _project.titles.length - 1);
        });
      case SelKind.sound:
        final a = _project.sounds[_sel.index];
        _edit(() {
          _project.sounds.add(
            AudioClip(
              a.path,
              a.name,
              startMs: a.endMs,
              trimStartMs: a.trimStartMs,
              durationMs: a.durationMs,
              sourceMs: a.sourceMs,
              volume: a.volume,
            ),
          );
          _sel = Selection(SelKind.sound, _project.sounds.length - 1);
        });
      case SelKind.music || SelKind.none:
        break;
    }
  }

  void _moveClip(int by) {
    final i = _sel.index;
    final to = i + by;
    if (to < 0 || to >= _project.clips.length) return;
    _edit(() {
      _project.move(i, by > 0 ? i + 2 : i - 1);
      _sel = Selection(SelKind.clip, to);
    });
  }

  // ---- Adding things ----

  Future<Media?> _pickMedia({required bool video}) {
    final library = context.read<MediaLibrary>();
    return showModalBottomSheet<Media>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, scroll) {
          final items = video ? library.videos : library.images;
          return Column(
            children: [
              ListTile(
                title: Text(
                  video ? 'Choisir une vidéo' : 'Choisir une photo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          video
                              ? 'Aucune vidéo trouvée'
                              : 'Aucune photo trouvée',
                        ),
                      )
                    : GridView.builder(
                        controller: scroll,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 120,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.pop(sheet, items[i]),
                          child: MediaThumb(items[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Video or photo to put at the end of the main track.
  Future<void> _addClip() async {
    final video = await _askVideoOrPhoto('Ajouter à la suite');
    if (video == null || !mounted) return;
    final picked = await _pickMedia(video: video);
    if (picked == null) return;
    _edit(() {
      _project.clips.add(VideoClip(picked));
      _sel = Selection(SelKind.clip, _project.clips.length - 1);
    });
    unawaited(_player.seek(_project.startOf(_project.clips.length - 1)));
  }

  Future<bool?> _askVideoOrPhoto(String title) {
    return showModalBottomSheet<bool>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Une vidéo'),
              onTap: () => Navigator.pop(sheet, true),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Une photo'),
              onTap: () => Navigator.pop(sheet, false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOverlay() async {
    final video = await _askVideoOrPhoto('Ajouter en incrustation');
    if (video == null || !mounted) return;
    final media = await _pickMedia(video: video);
    if (media == null || !mounted) return;
    final total = _project.totalMs;
    final start = math.min(_now, math.max(0, total - minClipMs));
    final o = OverlayClip(media, startMs: start);
    o.durationMs = math.max(
      minClipMs,
      math.min(o.durationMs, math.max(minClipMs, total - start)),
    );
    _edit(() {
      _project.overlays.add(o);
      _sel = Selection(SelKind.overlay, _project.overlays.length - 1);
      _panel = _Panel.overlay;
    });
  }

  Future<String?> _askText([String initial = '']) => showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(
      title: 'Texte',
      initial: initial,
      hint: 'Saisissez votre texte',
      multiline: true,
    ),
  );

  Future<void> _addText() async {
    final text = await _askText();
    if (text == null || text.isEmpty || !mounted) return;
    final total = _project.totalMs;
    final start = math.min(_now, math.max(0, total - 500));
    _edit(() {
      _project.titles.add(
        TitleItem(
          text,
          startMs: start,
          endMs: (start + 3000).clamp(
            start + 500,
            math.max(start + 500, total),
          ),
          size: 0.08,
          x: 0.5,
          y: 0.5,
          box: TitleBox.none,
          animation: TitleAnimation.fade,
        ),
      );
      _sel = Selection(SelKind.text, _project.titles.length - 1);
      _panel = _Panel.textStyle;
    });
  }

  static const _stickers = [
    '😀',
    '😂',
    '😍',
    '😎',
    '🥳',
    '😮',
    '😢',
    '😡',
    '❤️',
    '🔥',
    '⭐',
    '✨',
    '👍',
    '👏',
    '🎉',
    '🎬',
    '🎵',
    '📍',
    '☀️',
    '🌙',
    '🌈',
    '🌸',
    '🍕',
    '🚗',
    '➡️',
    '⬅️',
    '⬆️',
    '⬇️',
    '✅',
    '❌',
    '💯',
    '🆕',
  ];

  Future<void> _addSticker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final e in _stickers)
                Semantics(
                  button: true,
                  label: 'Autocollant $e',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(sheet, e),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    final total = _project.totalMs;
    final start = math.min(_now, math.max(0, total - 500));
    _edit(() {
      _project.titles.add(
        TitleItem(
          emoji,
          startMs: start,
          endMs: (start + 3000).clamp(
            start + 500,
            math.max(start + 500, total),
          ),
          size: 0.16,
          x: 0.5,
          y: 0.5,
          box: TitleBox.none,
          animation: TitleAnimation.pop,
        ),
      );
      _sel = Selection(SelKind.text, _project.titles.length - 1);
      _panel = _Panel.textStyle;
    });
  }

  // ---- Export ----

  Future<void> _export() async {
    final problem = _project.problem;
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    var dir = widget.outputDir;
    if (dir == null) {
      if (!await ensureFullFileAccess(context) || !mounted) return;
      dir = moviesDir;
    }
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final output = p.join(
      dir,
      'VID_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.mp4',
    );
    final library = context.read<MediaLibrary>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final progress = ValueNotifier<int>(0);
    var cancelled = false;

    // The preview is stopped so the encoder has the hardware to itself.
    _player.pause();
    if (!mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Création de la vidéo'),
            content: ValueListenableBuilder<int>(
              valueListenable: progress,
              builder: (_, percent, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: percent <= 0 ? null : percent / 100,
                  ),
                  const SizedBox(height: 12),
                  Text(percent <= 0 ? 'Préparation…' : '$percent %'),
                  const SizedBox(height: 8),
                  const Text(
                    "Gardez l'application ouverte pendant l'export.",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  MediaChannel.cancelExport();
                },
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
    unawaited(MediaChannel.keepScreenOn(true));
    String? saved;
    String? error;
    try {
      saved = await widget.exporter(
        _project.exportArgs(output),
        (v) => progress.value = v,
      );
    } on PlatformException catch (e) {
      error = e.message;
    } on Object catch (e) {
      error = '$e';
    }
    unawaited(MediaChannel.keepScreenOn(false));
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // progress dialog
    }
    progress.dispose();
    String? warning;
    if (saved != null &&
        !cancelled &&
        _project.overlays.any((o) => !o.isImage)) {
      warning = await MediaChannel.exportWarning();
    }
    if (!mounted) return;

    if (saved != null && !cancelled) {
      unawaited(
        MediaChannel.rescan([saved]).then((_) => library.load(request: false)),
      );
      _saveTimer?.cancel();
      _saveQuietly();
      _dirty = false;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              warning == null
                  ? 'Vidéo enregistrée dans Films / All-in-One'
                  : 'Vidéo enregistrée. $warning',
            ),
            duration: const Duration(seconds: 7),
            action: SnackBarAction(
              label: 'Partager',
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(files: [XFile(saved!)])),
            ),
          ),
        );
      navigator.pop(saved);
    } else if (cancelled) {
      showMessage(context, 'Export annulé');
    } else {
      showMessage(
        context,
        "L'export a échoué${error == null || error.isEmpty ? '' : ' : $error'}",
      );
    }
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _TextPrompt(title: 'Nom du projet', initial: _project.name),
    );
    if (name == null || name.isEmpty || !mounted) return;
    _edit(() => _project.name = name);
  }

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: Theme.of(context).colorScheme
            .copyWith(brightness: Brightness.dark),
      ),
      child: PopScope(
        // The montage is kept as a draft: leaving only saves it.
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && _dirty) _saveQuietly();
        },
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: Row(
                    children: [
                      _toolRail(),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: _previewArea()),
                                  if (_panel != null) _panelView(),
                                ],
                              ),
                            ),
                            _transport(),
                            _timeline(),
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
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 38,
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Flexible(
            child: InkWell(
              onTap: _rename,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  _project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.crop_rounded, size: 18),
            label: Text(_project.aspect.label),
            onPressed: () => _openPanel(_Panel.format),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _export,
            child: const Text('Exporter'),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _transport() {
    return Container(
      height: 34,
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: math.max(640.0, box.maxWidth),
            child: _transportRow(),
          ),
        ),
      ),
    );
  }

  Widget _transportRow() {
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: ValueListenableBuilder<int>(
            valueListenable: _player.time,
            builder: (_, t, _) => Text(
              '${clock(t)} / ${clock(_project.totalMs)}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Début',
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: () => _seek(0),
        ),
        IconButton(
          tooltip: _player.playing ? 'Pause' : 'Lecture',
          icon: Icon(
            _player.playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            size: 30,
          ),
          onPressed: _player.toggle,
        ),
        IconButton(
          tooltip: 'Fin',
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: () => _seek(_project.totalMs),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Annuler',
          icon: const Icon(Icons.undo_rounded),
          onPressed: _undo.isEmpty ? null : _undoStep,
        ),
        IconButton(
          tooltip: 'Rétablir',
          icon: const Icon(Icons.redo_rounded),
          onPressed: _redo.isEmpty ? null : _redoStep,
        ),
        IconButton(
          tooltip: 'Zoom arrière',
          icon: const Icon(Icons.zoom_out_rounded),
          onPressed: () =>
              setState(() => _ppm = (_ppm / 1.5).clamp(minPxPerMs, maxPxPerMs)),
        ),
        IconButton(
          tooltip: 'Zoom avant',
          icon: const Icon(Icons.zoom_in_rounded),
          onPressed: () =>
              setState(() => _ppm = (_ppm * 1.5).clamp(minPxPerMs, maxPxPerMs)),
        ),
      ],
    );
  }

  Widget _timeline() {
    return Container(
      height: (MediaQuery.sizeOf(context).height * 0.33).clamp(110.0, 170.0),
      color: const Color(0xFF111115),
      child: EditorTimeline(
        project: _project,
        time: _player.time,
        selection: _sel,
        pxPerMs: _ppm,
        onZoom: (z) => setState(() => _ppm = z),
        onSeek: _seek,
        onScrubStart: _scrubStart,
        onSelect: _select,
        onEdit: (change) {
          _merge = true;
          _edit(change);
        },
        onAddClip: _addClip,
        onTransition: (i) {
          setState(() {
            _sel = Selection(SelKind.clip, i);
            _panel = _Panel.transition;
          });
        },
      ),
    );
  }

  // ---- Tool rail ----

  Widget _toolRail() {
    final tools = _tools();
    return SizedBox(
      width: 70,
      child: Material(
        color: _surface,
        child: ListView(
          key: const ValueKey('tool-rail'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final t in tools)
              Semantics(
                button: true,
                enabled: t.enabled,
                selected: t.selected,
                label: t.label,
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey('tool-${t.label}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: t.enabled ? t.onTap : null,
                  child: SizedBox(
                    height: 52,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          t.icon,
                          size: 22,
                          color: !t.enabled
                              ? Colors.white24
                              : t.selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: !t.enabled
                                ? Colors.white24
                                : t.selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_Tool> _tools() {
    _Tool tool(
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool enabled = true,
      _Panel? panel,
    }) => _Tool(
      label,
      icon,
      onTap,
      enabled: enabled,
      selected: panel != null && _panel == panel,
    );

    final c = _clip;
    switch (_sel.kind) {
      case SelKind.none:
        return [
          tool('Média', Icons.add_photo_alternate_outlined, _addClip),
          tool('Diviser', Icons.content_cut_rounded, _split),
          tool(
            'Audio',
            Icons.music_note_rounded,
            () => _openPanel(_Panel.audio),
            panel: _Panel.audio,
          ),
          tool('Texte', Icons.title_rounded, _addText),
          tool('Autocollant', Icons.emoji_emotions_outlined, _addSticker),
          tool('Incrustation', Icons.layers_rounded, _addOverlay),
          tool(
            'Filtres',
            Icons.auto_awesome_rounded,
            () => _clipTool(_Panel.filters),
            panel: _Panel.filters,
          ),
          tool(
            'Effets',
            Icons.blur_on_rounded,
            () => _clipTool(_Panel.effects),
            panel: _Panel.effects,
          ),
          tool(
            'Format',
            Icons.crop_rounded,
            () => _openPanel(_Panel.format),
            panel: _Panel.format,
          ),
        ];
      case SelKind.clip:
        return [
          tool('Diviser', Icons.content_cut_rounded, _split),
          tool('Supprimer', Icons.delete_outline_rounded, _delete),
          tool(
            'Vitesse',
            Icons.speed_rounded,
            () => _openPanel(_Panel.speed),
            panel: _Panel.speed,
            enabled: c?.isImage == false,
          ),
          tool(
            'Volume',
            Icons.volume_up_rounded,
            () => _openPanel(_Panel.volume),
            panel: _Panel.volume,
            enabled: c?.isImage == false,
          ),
          tool(
            'Segment',
            Icons.vertical_split_rounded,
            () => _openPanel(_Panel.segment),
            panel: _Panel.segment,
            enabled: c?.isImage == false,
          ),
          tool(
            'Filtres',
            Icons.auto_awesome_rounded,
            () => _openPanel(_Panel.filters),
            panel: _Panel.filters,
          ),
          tool(
            'Ajuster',
            Icons.tune_rounded,
            () => _openPanel(_Panel.adjust),
            panel: _Panel.adjust,
          ),
          tool(
            'Effets',
            Icons.blur_on_rounded,
            () => _openPanel(_Panel.effects),
            panel: _Panel.effects,
          ),
          tool(
            'Transition',
            Icons.swap_horiz_rounded,
            () => _openPanel(_Panel.transition),
            panel: _Panel.transition,
          ),
          tool(
            'Format',
            Icons.crop_rounded,
            () => _openPanel(_Panel.format),
            panel: _Panel.format,
          ),
          tool(
            'Pivoter',
            Icons.rotate_right_rounded,
            () => _edit(() => c!.rotateClockwise()),
          ),
          tool(
            'Miroir',
            Icons.flip_rounded,
            () => _edit(() => c!.flip = !c.flip),
          ),
          tool(
            'Reculer',
            Icons.arrow_back_rounded,
            () => _moveClip(-1),
            enabled: _sel.index > 0,
          ),
          tool(
            'Avancer',
            Icons.arrow_forward_rounded,
            () => _moveClip(1),
            enabled: _sel.index < _project.clips.length - 1,
          ),
          tool('Dupliquer', Icons.copy_rounded, _duplicate),
        ];
      case SelKind.overlay:
        return [
          tool('Diviser', Icons.content_cut_rounded, _split),
          tool(
            'Réglages',
            Icons.tune_rounded,
            () => _openPanel(_Panel.overlay),
            panel: _Panel.overlay,
          ),
          tool('Dupliquer', Icons.copy_rounded, _duplicate),
          tool('Supprimer', Icons.delete_outline_rounded, _delete),
        ];
      case SelKind.text:
        return [
          tool('Diviser', Icons.content_cut_rounded, _split),
          tool('Modifier', Icons.edit_outlined, _editText),
          tool(
            'Style',
            Icons.text_fields_rounded,
            () => _openPanel(_Panel.textStyle),
            panel: _Panel.textStyle,
          ),
          tool('Dupliquer', Icons.copy_rounded, _duplicate),
          tool('Supprimer', Icons.delete_outline_rounded, _delete),
        ];
      case SelKind.sound:
        return [
          tool('Diviser', Icons.content_cut_rounded, _split),
          tool(
            'Volume',
            Icons.volume_up_rounded,
            () => _openPanel(_Panel.sound),
            panel: _Panel.sound,
          ),
          tool('Dupliquer', Icons.copy_rounded, _duplicate),
          tool('Supprimer', Icons.delete_outline_rounded, _delete),
        ];
      case SelKind.music:
        return [
          tool(
            'Volume',
            Icons.volume_up_rounded,
            () => _openPanel(_Panel.audio),
            panel: _Panel.audio,
          ),
          tool('Supprimer', Icons.delete_outline_rounded, _delete),
        ];
    }
  }

  Future<void> _editText() async {
    if (_sel.kind != SelKind.text) return;
    final t = _project.titles[_sel.index];
    final text = await _askText(t.text);
    if (text != null && text.isNotEmpty && mounted) _edit(() => t.text = text);
  }

  // ---- Preview ----

  Widget _previewArea() {
    return Container(
      color: Colors.black,
      child: Center(child: _framed()),
    );
  }

  /// The picture of the clip under the playhead with its look, mirror, blur,
  /// motion and transitions, in the frame of the montage, with the live
  /// layers (texts, stickers, overlaid pictures) on top.
  Widget _framed() {
    return ValueListenableBuilder<int>(
      valueListenable: _player.time,
      builder: (context, now, _) {
        final (index, offset) = _project.locate(now);
        final c = _project.clips[index];
        final size = c.orientedSize;
        final w = size.width <= 0 ? 16.0 : size.width;
        final h = size.height <= 0 ? 9.0 : size.height;
        final aspect = _project.aspect;
        final ratio = aspect == Aspect.original ? w / h : aspect.ratio;

        final controller = _player.controller;
        Widget source;
        double sourceAspect = w / h;
        if (c.isImage) {
          source = Image.file(
            File(c.media.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
          );
          if (c.media.width > 0 && c.media.height > 0) {
            sourceAspect = c.media.width / c.media.height;
          }
        } else if (controller != null && controller.value.isInitialized) {
          source = VideoPlayer(controller);
          sourceAspect = controller.value.aspectRatio;
        } else {
          source = ColoredBox(
            color: Colors.black,
            child: Center(
              child: _player.failed
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.videocam_off_outlined,
                          color: Colors.white38,
                          size: 36,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Aperçu indisponible',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    )
                  : const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          );
        }

        Widget video = AspectRatio(aspectRatio: sourceAspect, child: source);
        final look = c.look;
        if (!look.isNeutral) {
          video = ColorFiltered(
            colorFilter: ColorFilter.matrix(look.preview5x4),
            child: video,
          );
        }
        if (c.blur > 0) {
          video = ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: c.blur * 8,
              sigmaY: c.blur * 8,
              tileMode: TileMode.clamp,
            ),
            child: video,
          );
        }
        video = RotatedBox(quarterTurns: c.rotation ~/ 90, child: video);
        if (c.flip) video = Transform.flip(flipX: true, child: video);

        final pose = _project.poseAt(index, offset);
        final Widget base = FittedBox(
          fit: _project.fillFrame && aspect != Aspect.original
              ? BoxFit.cover
              : BoxFit.contain,
          child: SizedBox(width: w, height: h, child: video),
        );
        Widget picture = base;
        if (!pose.isNeutral) {
          picture = LayoutBuilder(
            builder: (_, box) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(
                  pose.dx * box.maxWidth / 2,
                  -pose.dy * box.maxHeight / 2,
                  0,
                  1,
                )
                ..scaleByDouble(pose.scale, pose.scale, 1, 1),
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix([
                  pose.gain, 0, 0, 0, 0, //
                  0, pose.gain, 0, 0, 0,
                  0, 0, pose.gain, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: base,
              ),
            ),
          );
        }
        return AspectRatio(
          aspectRatio: ratio,
          child: GestureDetector(
            onTap: _player.toggle,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  picture,
                  _layersOnPreview(now),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Titles, stickers and overlaid pictures at the playhead. The selected
  /// one can be dragged to place it.
  Widget _layersOnPreview(int now) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final children = <Widget>[];
        final sorted = [..._project.overlays.indexed]
          ..sort((a, b) => a.$2.track.compareTo(b.$2.track));
        for (final (i, o) in sorted) {
          if (now < o.startMs || now >= o.endMs) continue;
          final selected = _sel.is_(SelKind.overlay, i);
          final aspect = o.media.width > 0 && o.media.height > 0
              ? o.media.width / o.media.height
              : 16 / 9;
          children.add(
            Positioned(
              left: o.cx * w,
              top: o.cy * h,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: GestureDetector(
                  onTap: () => _select(Selection(SelKind.overlay, i)),
                  onPanUpdate: selected
                      ? (d) => _drag(() {
                          o.cx = (o.cx + d.delta.dx / w).clamp(0.0, 1.0);
                          o.cy = (o.cy + d.delta.dy / h).clamp(0.0, 1.0);
                        })
                      : null,
                  child: Opacity(
                    opacity: o.opacity,
                    child: Container(
                      width: o.width * w,
                      height: o.width * w / aspect,
                      decoration: BoxDecoration(
                        border: selected
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: o.isImage
                          ? Image.file(
                              File(o.media.path),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Colors.black26),
                            )
                          : MediaThumb(o.media, showDuration: false),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        for (final (i, t) in _project.titles.indexed) {
          if (now < t.startMs || now >= t.endMs || t.text.trim().isEmpty) {
            continue;
          }
          final selected = _sel.is_(SelKind.text, i);
          final label = Container(
            padding: t.box == TitleBox.none
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: switch (t.box) {
                TitleBox.none => null,
                TitleBox.shade => const Color(0x8C000000),
                TitleBox.solid => const Color(0xFF141418),
              },
              border: selected
                  ? Border.all(color: Colors.white70, width: 1.5)
                  : null,
            ),
            child: Text(
              t.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(t.color),
                fontWeight: FontWeight.w700,
                fontSize: math.max(8.0, t.size * h),
                height: 1.1,
              ),
            ),
          );
          final tap = GestureDetector(
            onTap: () => _select(Selection(SelKind.text, i)),
            onPanUpdate: selected
                ? (d) => _drag(() {
                    t.x = ((t.x ?? _homeX(t)) + d.delta.dx / w).clamp(0.0, 1.0);
                    t.y = ((t.y ?? _homeY(t)) + d.delta.dy / h).clamp(0.0, 1.0);
                  })
                : null,
            child: label,
          );
          children.add(
            Positioned(
              left: (t.x ?? _homeX(t)) * w,
              top: (t.y ?? _homeY(t)) * h,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: tap,
              ),
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  double _homeX(TitleItem t) => 0.5 + t.align * 0.35;
  double _homeY(TitleItem t) => switch (t.place) {
    TitlePlace.top => 0.1,
    TitlePlace.middle => 0.5,
    TitlePlace.bottom => 0.9,
  };
}

/// A button of the tool rail.
class _Tool {
  const _Tool(
    this.label,
    this.icon,
    this.onTap, {
    this.enabled = true,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool selected;
}

/// A dialog asking for one piece of text; it owns its controller so it is
/// released only once the dialog has left the screen.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.initial,
    this.hint,
    this.multiline = false,
  });

  final String title;
  final String initial;
  final String? hint;
  final bool multiline;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.multiline ? 3 : 1,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
