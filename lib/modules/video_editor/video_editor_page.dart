import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../gallery/media_grid.dart';
import '../gallery/media_library.dart';
import 'project_store.dart';
import 'video_project.dart';

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

enum _Tab {
  trim('Couper', Icons.content_cut_rounded),
  speed('Vitesse', Icons.speed_rounded),
  audio('Audio', Icons.music_note_rounded),
  titles('Titres', Icons.title_rounded),
  fades('Fondus', Icons.gradient_rounded);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Montage editor: trim, join, speed, rotation and music, exported as a
/// new MP4. The source videos are never changed.
class VideoEditorPage extends StatefulWidget {
  const VideoEditorPage({
    super.key,
    this.media,
    this.project,
    this.store,
    this.exporter = nativeExport,
    this.outputDir,
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

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  late final VideoProject _project =
      widget.project ?? VideoProject(widget.media!);
  late final ProjectStore _store = widget.store ?? ProjectStore();
  Timer? _saveTimer;
  int _selectedTitle = -1;
  int _selected = 0;
  _Tab _tab = _Tab.trim;
  bool _dirty = false;

  VideoPlayerController? _player;
  int _playerFor = -1;
  bool _previewFailed = false;

  Clip get _clip => _project.clips[_selected];

  @override
  void initState() {
    super.initState();
    // Not in initState itself: opening the preview updates the state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPreview();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Whatever was done since the last save is kept.
    if (_dirty) _saveQuietly();
    _player?.dispose();
    super.dispose();
  }

  /// Opens the selected clip in the preview and learns its displayed size.
  Future<void> _openPreview() async {
    final clip = _clip;
    final index = _selected;
    _playerFor = index;
    final old = _player;
    _player = null;
    setState(() => _previewFailed = false);
    try {
      await old?.dispose();
    } on Object {
      // Already released.
    }
    VideoPlayerController? controller;
    try {
      controller = clip.media.uri.startsWith('content:')
          ? VideoPlayerController.contentUri(Uri.parse(clip.media.uri))
          : VideoPlayerController.file(File(clip.media.path));
      // A file the player cannot open must not leave the spinner running.
      await controller.initialize().timeout(const Duration(seconds: 10));
      if (!mounted || _playerFor != index) {
        await controller.dispose();
        return;
      }
      clip.shownSize ??= controller.value.size;
      await controller.setLooping(false);
      await controller.setPlaybackSpeed(clip.speed);
      await controller.seekTo(Duration(milliseconds: clip.startMs));
      controller.addListener(_loop);
      setState(() => _player = controller);
    } on Object {
      // No preview (unsupported file or no player): editing still works.
      if (mounted && _playerFor == index) setState(() => _previewFailed = true);
      try {
        await controller?.dispose();
      } on Object {
        // Releasing a player that never opened can fail; nothing to do.
      }
    }
  }

  /// Plays only the kept part: back to its start when it ends.
  void _loop() {
    final c = _player;
    if (c == null || !c.value.isInitialized) return;
    final clip = _project.clips[_selected.clamp(0, _project.clips.length - 1)];
    if (c.value.position.inMilliseconds >= clip.endMs) {
      c.seekTo(Duration(milliseconds: clip.startMs));
    }
  }

  /// Saving the montage must never get in the way of editing or exporting.
  void _saveQuietly() {
    _store.save(_project).catchError((Object _) {});
  }

  void _edit(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
    });
    // The montage is saved a moment after the last change.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveQuietly);
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    _openPreview();
  }

  void _seekTo(int ms) => _player?.seekTo(Duration(milliseconds: ms));

  // ---- Clips ----

  Future<void> _addClip() async {
    final library = context.read<MediaLibrary>();
    final picked = await showModalBottomSheet<Media>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) {
          final videos = library.videos;
          return Column(
            children: [
              ListTile(
                title: Text(
                  'Ajouter une vidéo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: videos.isEmpty
                    ? const Center(child: Text('Aucune vidéo trouvée'))
                    : GridView.builder(
                        controller: scroll,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        itemCount: videos.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.pop(sheet, videos[i]),
                          child: MediaThumb(videos[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null) return;
    _edit(() {
      _project.clips.add(Clip(picked));
      _selected = _project.clips.length - 1;
    });
    unawaited(_openPreview());
  }

  void _removeClip() {
    if (_project.clips.length == 1) {
      showMessage(context, 'Il faut garder au moins une vidéo');
      return;
    }
    _edit(() {
      _project.clips.removeAt(_selected);
      _selected = _selected.clamp(0, _project.clips.length - 1);
    });
    unawaited(_openPreview());
  }

  /// Cuts the selected clip in two at the preview's position.
  void _split() {
    final player = _player;
    final at = player?.value.position.inMilliseconds;
    if (at == null) {
      showMessage(context, "Attendez l'aperçu pour choisir où couper");
      return;
    }
    final index = _selected;
    var done = false;
    _edit(() {
      done = _project.split(index, at);
      if (done) _selected = index + 1;
    });
    if (!done) {
      showMessage(context, 'Placez la lecture à plus de 0,5 s des extrémités');
    } else {
      unawaited(_openPreview());
    }
  }

  void _duplicateClip() {
    _edit(() {
      _project.clips.insert(_selected + 1, _clip.copy());
      _selected += 1;
    });
    unawaited(_openPreview());
  }

  // ---- Music ----

  Future<void> _pickMusic() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.audio);
      if (file == null) return;
      var path = file.path;
      if (path == null) {
        // A content:// address: copy it to a real file for the exporter.
        final dir = Directory(
          '${(await getTemporaryDirectory()).path}/montage',
        );
        await dir.create(recursive: true);
        final copy = File(await uniquePath(dir.path, file.name));
        final sink = copy.openWrite();
        await sink.addStream(file.xFile.openRead());
        await sink.close();
        path = copy.path;
      }
      _edit(() {
        _project
          ..musicPath = path
          ..musicName = file.name;
      });
    } on Object {
      if (mounted) showMessage(context, 'Impossible de lire ce fichier audio');
    }
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
    await _player?.pause();
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
            content: const Text('Vidéo enregistrée dans Films / All-in-One'),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clips = _project.clips;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Abandonner le montage ?'),
            content: const Text('Les changements non exportés seront perdus.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Continuer'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Abandonner'),
              ),
            ],
          ),
        );
        if (leave == true) navigator.pop();
      },
      child: Theme(
        // A complete dark theme: only swapping the colour scheme would keep
        // the light theme's dark text colours.
        data: buildTheme(scheme.primary, Brightness.dark),
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF101014),
            appBar: AppBar(
              backgroundColor: const Color(0xFF101014),
              leading: IconButton(
                tooltip: 'Fermer',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('Montage'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(
                    onPressed: _export,
                    child: const Text('Exporter'),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(child: _preview()),
                _scrubber(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Durée finale ${clock(_project.totalMs)} · ${clips.length} extrait${clips.length > 1 ? 's' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Scinder ici',
                        icon: const Icon(Icons.call_split_rounded),
                        onPressed: _split,
                      ),
                      IconButton(
                        tooltip: 'Pivoter à droite',
                        icon: const Icon(Icons.rotate_right_rounded),
                        onPressed: () => _edit(() => _clip.rotateClockwise()),
                      ),
                      IconButton(
                        tooltip: 'Dupliquer',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: _duplicateClip,
                      ),
                      IconButton(
                        tooltip: "Supprimer l'extrait",
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _removeClip,
                      ),
                    ],
                  ),
                ),
                _strip(),
                // A Material, so list tiles inside can show their touch effect.
                Material(
                  color: const Color(0xFF17171C),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 120,
                      maxHeight: 250,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SingleChildScrollView(
                      child: switch (_tab) {
                        _Tab.trim => _trimPanel(),
                        _Tab.speed => _speedPanel(),
                        _Tab.audio => _audioPanel(),
                        _Tab.titles => _titlesPanel(),
                        _Tab.fades => _fadesPanel(),
                      },
                    ),
                  ),
                ),
                NavigationBar(
                  backgroundColor: const Color(0xFF17171C),
                  selectedIndex: _tab.index,
                  onDestinationSelected: (i) =>
                      setState(() => _tab = _Tab.values[i]),
                  destinations: [
                    for (final t in _Tab.values)
                      NavigationDestination(icon: Icon(t.icon), label: t.label),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final player = _player;
    return Center(
      child: player != null && player.value.isInitialized
          ? GestureDetector(
              onTap: () =>
                  player.value.isPlaying ? player.pause() : player.play(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotatedBox(
                    quarterTurns: _clip.rotation ~/ 90,
                    child: AspectRatio(
                      aspectRatio: player.value.aspectRatio,
                      child: VideoPlayer(player),
                    ),
                  ),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: player,
                    builder: (_, v, _) => AnimatedOpacity(
                      opacity: v.isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: const CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.black54,
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_previewFailed) ...[
                  const Icon(
                    Icons.videocam_off_outlined,
                    size: 48,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aperçu indisponible',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const Text(
                    'Le montage reste possible.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ] else
                  const CircularProgressIndicator(),
              ],
            ),
    );
  }

  Widget _strip() {
    final clips = _project.clips;
    return SizedBox(
      height: 92,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              buildDefaultDragHandles: false,
              itemCount: clips.length,
              onReorderItem: (from, to) {
                // `to` is already the final position; the model expects
                // the slot before removal.
                final selectedClip = _clip;
                _edit(() {
                  _project.move(from, to > from ? to + 1 : to);
                  _selected = _project.clips.indexOf(selectedClip);
                });
              },
              itemBuilder: (_, i) {
                final c = clips[i];
                final selected = i == _selected;
                return ReorderableDelayedDragStartListener(
                  key: ObjectKey(c),
                  index: i,
                  child: GestureDetector(
                    onTap: () => _select(i),
                    child: Container(
                      width: (72 + c.outputMs / 1000 * 10)
                          .clamp(72, 240)
                          .toDouble(),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          width: 2.5,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaThumb(c.media, showDuration: false),
                            if (c.fade)
                              const Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(
                                  Icons.gradient_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  '${clock(c.outputMs)}${c.speed != 1 ? ' · ${formatNumber(c.speed)}×' : ''}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Ajouter une vidéo',
              icon: const Icon(Icons.add_rounded),
              onPressed: _addClip,
            ),
          ),
        ],
      ),
    );
  }

  /// Position slider over the kept part of the selected clip.
  Widget _scrubber() {
    final player = _player;
    final c = _clip;
    if (player == null || !player.value.isInitialized) {
      return const SizedBox(height: 4);
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (_, v, _) {
        final min = c.startMs.toDouble();
        final max = c.endMs.toDouble();
        return SizedBox(
          height: 32,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Text(
                clock(v.position.inMilliseconds.clamp(c.startMs, c.endMs)),
                style: const TextStyle(fontSize: 11),
              ),
              Expanded(
                child: Slider(
                  min: min,
                  max: max > min ? max : min + 1,
                  value: v.position.inMilliseconds
                      .clamp(c.startMs, c.endMs)
                      .toDouble(),
                  onChanged: (ms) => _seekTo(ms.round()),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _askTitleText([String initial = '']) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Texte du titre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static const _titleColors = <int>[
    0xFFFFFFFF,
    0xFFFFC53D,
    0xFFE5484D,
    0xFF0A84FF,
    0xFF30A46C,
  ];

  Widget _titlesPanel() {
    final titles = _project.titles;
    final total = _project.totalMs;
    final sel = _selectedTitle >= 0 && _selectedTitle < titles.length
        ? titles[_selectedTitle]
        : null;
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un titre'),
                  onPressed: () async {
                    final text = await _askTitleText();
                    if (text == null || text.isEmpty) return;
                    // Starts where the preview is, in the finished video.
                    final at =
                        _project.startOf(_selected) +
                        (((_player?.value.position.inMilliseconds ??
                                        _clip.startMs) -
                                    _clip.startMs) /
                                _clip.speed)
                            .round();
                    final start = at.clamp(0, total > 1000 ? total - 500 : 0);
                    _edit(() {
                      titles.add(
                        TitleItem(
                          text,
                          startMs: start,
                          endMs: (start + 3000).clamp(start + 500, total),
                        ),
                      );
                      _selectedTitle = titles.length - 1;
                    });
                  },
                ),
              ),
              for (final (i, t) in titles.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        t.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: i == _selectedTitle,
                    onSelected: (_) => setState(() => _selectedTitle = i),
                  ),
                ),
            ],
          ),
        ),
        if (sel == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Placez la lecture à l\'endroit voulu, puis ajoutez un titre. Il apparaît à l\'écran pendant la durée choisie.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          )
        else ...[
          RangeSlider(
            min: 0,
            max: total <= 0 ? 1.0 : total.toDouble(),
            values: RangeValues(
              sel.startMs.clamp(0, total).toDouble(),
              sel.endMs
                  .clamp(
                    sel.startMs.clamp(0, total) + 1,
                    total <= 0 ? 1 : total,
                  )
                  .toDouble(),
            ),
            onChanged: (v) => _edit(() {
              sel.startMs = v.start.round();
              sel.endMs = v.end.round().clamp(sel.startMs + 300, total + 300);
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Affiché de ${clock(sel.startMs)} à ${clock(sel.endMs.clamp(0, total))}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final place in TitlePlace.values)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(place.label),
                    selected: sel.place == place,
                    onSelected: (_) => _edit(() => sel.place = place),
                  ),
                for (final (label, size) in const [
                  ('A', 0.04),
                  ('A+', 0.06),
                  ('A++', 0.09),
                ])
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(label),
                    selected: sel.size == size,
                    onSelected: (_) => _edit(() => sel.size = size),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 12),
              for (final c in _titleColors)
                Semantics(
                  label: 'Couleur du titre',
                  button: true,
                  child: GestureDetector(
                    onTap: () => _edit(() => sel.color = c),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: sel.color == c ? 3 : 1,
                            color: sel.color == c
                                ? Colors.white70
                                : Colors.white24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Modifier le texte',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final text = await _askTitleText(sel.text);
                  if (text != null && text.isNotEmpty) {
                    _edit(() => sel.text = text);
                  }
                },
              ),
              IconButton(
                tooltip: 'Supprimer le titre',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _edit(() {
                  titles.remove(sel);
                  _selectedTitle = -1;
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _fadesPanel() {
    final c = _clip;
    final last = _selected == _project.clips.length - 1;
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: const Text("Fondu d'ouverture"),
          subtitle: const Text('La vidéo apparaît depuis le noir'),
          value: _project.openingFade,
          onChanged: (v) => _edit(() => _project.openingFade = v),
        ),
        SwitchListTile(
          dense: true,
          title: Text(
            last ? 'Fondu de fermeture' : 'Transition vers le suivant',
          ),
          subtitle: Text(
            last
                ? "La vidéo s'éteint vers le noir à la fin"
                : "Fondu au noir à la fin de cet extrait, puis réapparition",
          ),
          value: c.fade,
          onChanged: (v) => _edit(() => c.fade = v),
        ),
      ],
    );
  }

  Widget _trimPanel() {
    final c = _clip;
    final max = c.sourceMs <= 0 ? 1.0 : c.sourceMs.toDouble();
    return Column(
      children: [
        RangeSlider(
          min: 0,
          max: max,
          values: RangeValues(c.startMs.toDouble(), c.endMs.toDouble()),
          onChanged: (v) {
            final startMoved = v.start.round() != c.startMs;
            _edit(() {
              c.setStart(v.start.round());
              c.setEnd(v.end.round());
            });
            // The preview follows the handle being dragged.
            _seekTo(
              startMoved
                  ? c.startMs
                  : (c.endMs - 700).clamp(c.startMs, c.endMs),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Début ${clock(c.startMs)}'),
              Text(
                'Durée ${clock(c.keptMs)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('Fin ${clock(c.endMs)}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _speedPanel() {
    final c = _clip;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in speedChoices)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text('${formatNumber(s)}×'),
                  selected: c.speed == s,
                  onSelected: (_) {
                    _edit(() => c.speed = s);
                    _player?.setPlaybackSpeed(s);
                  },
                ),
            ],
          ),
        ),
        Text(
          'Cet extrait dure ${clock(c.outputMs)} après ce réglage.',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _audioPanel() {
    final hasMusic = _project.musicPath != null;
    final c = _clip;
    return Column(
      children: [
        if (!(_project.muteOriginal || hasMusic))
          Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.volume_up_rounded, size: 20),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: '${(c.volume * 100).round()} %',
                  value: c.volume.clamp(0.0, 2.0),
                  onChanged: (v) => _edit(() => c.volume = v),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  'Cet extrait\n${(c.volume * 100).round()} %',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        if (hasMusic)
          Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.music_note_rounded, size: 20),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: '${(_project.musicVolume * 100).round()} %',
                  value: _project.musicVolume.clamp(0.0, 2.0),
                  onChanged: (v) => _edit(() => _project.musicVolume = v),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  'Musique\n${(_project.musicVolume * 100).round()} %',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        SwitchListTile(
          dense: true,
          title: const Text("Couper le son d'origine"),
          subtitle: const Text('Pour toutes les vidéos du montage'),
          value: _project.muteOriginal || hasMusic,
          // With music, the original sound is always replaced.
          onChanged: hasMusic
              ? null
              : (v) => _edit(() => _project.muteOriginal = v),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.library_music_outlined),
          title: Text(hasMusic ? _project.musicName! : 'Ajouter une musique'),
          subtitle: Text(
            hasMusic
                ? 'Répétée et coupée à la fin du montage'
                : 'Elle remplace le son des vidéos',
          ),
          trailing: hasMusic
              ? IconButton(
                  tooltip: 'Retirer la musique',
                  icon: const Icon(Icons.close),
                  onPressed: () => _edit(() {
                    _project
                      ..musicPath = null
                      ..musicName = null;
                  }),
                )
              : null,
          onTap: _pickMusic,
        ),
      ],
    );
  }
}
