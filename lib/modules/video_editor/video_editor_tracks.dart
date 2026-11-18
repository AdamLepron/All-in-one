part of 'video_editor_page.dart';

/// Multitrack timeline, layers, sounds, transitions and cuts of the editor.
/// Kept apart from the main file; everything here belongs to its state.

/// One bar on the timeline.
class _Block {
  const _Block(
    this.start,
    this.end,
    this.label,
    this.color,
    this.onTap, {
    this.selected = false,
  });
  final int start;
  final int end;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
}

class _Lane {
  const _Lane(this.icon, this.blocks);
  final IconData icon;
  final List<_Block> blocks;
}

extension _TracksUi on _VideoEditorPageState {
  // ---- Timeline ----

  List<_Lane> _lanes() {
    final lanes = <_Lane>[];
    final p = _project;
    lanes.add(
      _Lane(Icons.movie_outlined, [
        for (final (i, c) in p.clips.indexed)
          _Block(
            p.startOf(i),
            p.startOf(i) + c.outputMs,
            c.isImage ? '🖼' : '${i + 1}',
            const Color(0xFF5B5BD6),
            () => _select(i),
            selected: i == _selected && _selOverlay < 0,
          ),
      ]),
    );
    final usedLanes = {for (final o in p.overlays) o.track}.toList()..sort();
    for (final lane in usedLanes) {
      lanes.add(
        _Lane(Icons.layers_outlined, [
          for (final (i, o) in p.overlays.indexed)
            if (o.track == lane)
              _Block(
                o.startMs,
                o.endMs,
                o.isImage ? '🖼' : '▶',
                const Color(0xFF00897B),
                () => _pickOverlay(i),
                selected: i == _selOverlay,
              ),
        ]),
      );
    }
    if (p.titles.isNotEmpty) {
      lanes.add(
        _Lane(Icons.title_rounded, [
          for (final (i, t) in p.titles.indexed)
            _Block(
              t.startMs,
              t.endMs,
              t.text,
              const Color(0xFFEF6C00),
              () => _pickTitle(i),
              selected: i == _selectedTitle && _tab == _Tab.titles,
            ),
        ]),
      );
    }
    if (p.musicPath != null) {
      lanes.add(
        _Lane(Icons.music_note_rounded, [
          _Block(
            0,
            p.totalMs,
            p.musicName ?? 'Musique',
            const Color(0xFF8E24AA),
            () => _ui(() => _tab = _Tab.audio),
          ),
        ]),
      );
    }
    // Sounds share a lane while they do not overlap.
    final soundLanes = <List<_Block>>[];
    for (final (i, a) in p.sounds.indexed) {
      final block = _Block(
        a.startMs,
        a.endMs,
        a.name,
        const Color(0xFFD81B60),
        () => _pickSound(i),
        selected: i == _selSound,
      );
      final lane = soundLanes.where((l) => l.last.end <= a.startMs).firstOrNull;
      if (lane != null) {
        lane.add(block);
      } else {
        soundLanes.add([block]);
      }
    }
    for (final l in soundLanes) {
      lanes.add(_Lane(Icons.graphic_eq_rounded, l));
    }
    return lanes;
  }

  void _pickOverlay(int i) => _ui(() {
    _selOverlay = i;
    _tab = _Tab.layers;
  });

  void _pickTitle(int i) => _ui(() {
    _selectedTitle = i;
    _tab = _Tab.titles;
  });

  void _pickSound(int i) => _ui(() {
    _selSound = i;
    _tab = _Tab.audio;
  });

  Widget _timeline() {
    final lanes = _lanes();
    final total = math.max(1, _project.totalMs);
    const iconWidth = 26.0;
    const rowHeight = 20.0;
    final height = math.min(lanes.length * (rowHeight + 2) + 4, 88.0);
    return Container(
      height: height,
      color: const Color(0xFF111115),
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, box) {
            final span = math.max(40.0, box.maxWidth - iconWidth - 12);
            final k = span / total;
            return SizedBox(
              height: lanes.length * (rowHeight + 2) + 4,
              child: Stack(
                children: [
                  for (final (r, lane) in lanes.indexed) ...[
                    Positioned(
                      left: 4,
                      top: 2 + r * (rowHeight + 2),
                      width: iconWidth - 4,
                      height: rowHeight,
                      child: Icon(lane.icon, size: 14, color: Colors.white54),
                    ),
                    for (final b in lane.blocks)
                      Positioned(
                        left: iconWidth + b.start * k,
                        top: 2 + r * (rowHeight + 2),
                        width: math.max(14.0, (b.end - b.start) * k),
                        height: rowHeight,
                        child: Semantics(
                          button: true,
                          label: 'Piste ${b.label}',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: b.onTap,
                            child: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                color: b.color.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  width: b.selected ? 2 : 0.5,
                                  color: b.selected
                                      ? Colors.white
                                      : Colors.white24,
                                ),
                              ),
                              child: Text(
                                b.label,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  // The playhead.
                  ValueListenableBuilder<int>(
                    valueListenable: _pos,
                    builder: (_, ms, _) {
                      final t =
                          _project.startOf(
                            _selected.clamp(0, _project.clips.length - 1),
                          ) +
                          ms;
                      return Positioned(
                        left: iconWidth + t.clamp(0, total) * k - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: const ColoredBox(color: Colors.white),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---- Live layers over the preview ----

  /// Moment of the finished video shown now, for the layers.
  int _timelineNow() =>
      _project.startOf(_selected.clamp(0, _project.clips.length - 1)) +
      _pos.value;

  Widget _layersOnPreview() {
    return ValueListenableBuilder<int>(
      valueListenable: _pos,
      builder: (_, _, _) {
        final now = _timelineNow();
        return LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            final children = <Widget>[];
            final sorted = [..._project.overlays.indexed]
              ..sort((a, b) => a.$2.track.compareTo(b.$2.track));
            for (final (i, o) in sorted) {
              if (now < o.startMs || now >= o.endMs) continue;
              final width = o.width * w;
              final selected = i == _selOverlay && _tab == _Tab.layers;
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
                      onTap: () => _pickOverlay(i),
                      onPanUpdate: selected
                          ? (d) => _edit(() {
                              o.cx = (o.cx + d.delta.dx / w).clamp(0.0, 1.0);
                              o.cy = (o.cy + d.delta.dy / h).clamp(0.0, 1.0);
                            })
                          : null,
                      child: Opacity(
                        opacity: o.opacity,
                        child: Container(
                          width: width,
                          height: width / aspect,
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
              final selected = i == _selectedTitle && _tab == _Tab.titles;
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
                  style: TextStyle(
                    color: Color(t.color),
                    fontWeight: FontWeight.w700,
                    fontSize: math.max(8.0, t.size * h),
                    height: 1.1,
                  ),
                ),
              );
              final drag = selected
                  ? (DragUpdateDetails d) => _edit(() {
                      t.x = ((t.x ?? _titleHomeX(t)) + d.delta.dx / w).clamp(
                        0.0,
                        1.0,
                      );
                      t.y = ((t.y ?? _titleHomeY(t)) + d.delta.dy / h).clamp(
                        0.0,
                        1.0,
                      );
                    })
                  : null;
              final tap = GestureDetector(
                onTap: () => _pickTitle(i),
                onPanUpdate: drag,
                child: label,
              );
              children.add(
                t.x != null && t.y != null
                    ? Positioned(
                        left: t.x! * w,
                        top: t.y! * h,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: tap,
                        ),
                      )
                    : Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Padding(
                          padding: EdgeInsets.all(h * 0.04),
                          child: Align(
                            alignment: Alignment(
                              t.align.toDouble(),
                              switch (t.place) {
                                TitlePlace.top => -1,
                                TitlePlace.middle => 0,
                                TitlePlace.bottom => 1,
                              },
                            ),
                            child: tap,
                          ),
                        ),
                      ),
              );
            }
            return Stack(children: children);
          },
        );
      },
    );
  }

  /// Where a title sits, as fractions of the frame, before it is dragged.
  double _titleHomeX(TitleItem t) => 0.5 + t.align * 0.35;
  double _titleHomeY(TitleItem t) => switch (t.place) {
    TitlePlace.top => 0.1,
    TitlePlace.middle => 0.5,
    TitlePlace.bottom => 0.9,
  };

  // ---- Pickers ----

  Future<Media?> _pickMedia({required bool video}) {
    final library = context.read<MediaLibrary>();
    return showModalBottomSheet<Media>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
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
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
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

  /// Where the playhead is in the finished video.
  int get _playheadMs => _timelineNow().clamp(0, math.max(0, _project.totalMs));

  // ---- Layers panel ----

  Future<void> _addOverlay({required bool video}) async {
    final media = await _pickMedia(video: video);
    if (media == null || !mounted) return;
    final total = _project.totalMs;
    final start = math.min(_playheadMs, math.max(0, total - minClipMs));
    final o = OverlayClip(media, startMs: start);
    o.durationMs = math.max(
      minClipMs,
      math.min(o.durationMs, math.max(minClipMs, total - start)),
    );
    _edit(() {
      _project.overlays.add(o);
      _selOverlay = _project.overlays.length - 1;
      _tab = _Tab.layers;
    });
  }

  Widget _layersPanel() {
    final overlays = _project.overlays;
    final sel = _selOverlay >= 0 && _selOverlay < overlays.length
        ? overlays[_selOverlay]
        : null;
    final total = math.max(1, _project.totalMs);
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
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Ajouter une image'),
                  onPressed: () => _addOverlay(video: false),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('Ajouter une vidéo'),
                  onPressed: () => _addOverlay(video: true),
                ),
              ),
              for (final (i, o) in overlays.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(
                      o.isImage
                          ? Icons.image_outlined
                          : Icons.videocam_outlined,
                      size: 16,
                    ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        o.media.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: i == _selOverlay,
                    onSelected: (_) => _ui(() => _selOverlay = i),
                  ),
                ),
            ],
          ),
        ),
        if (sel == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Ajoutez une image ou une vidéo : elle s'affiche par-dessus le montage, à l'endroit et pendant le temps choisis. Glissez-la dans l'aperçu pour la placer.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          )
        else ...[
          RangeSlider(
            min: 0,
            max: total.toDouble(),
            values: RangeValues(
              sel.startMs.clamp(0, total).toDouble(),
              sel.endMs
                  .clamp(sel.startMs.clamp(0, total) + 1, total)
                  .toDouble(),
            ),
            onChanged: (v) => _edit(() {
              final start = v.start.round().clamp(0, total - minClipMs);
              var end = v.end.round().clamp(start + minClipMs, total);
              if (end - start > sel.maxDurationMs) {
                end = start + sel.maxDurationMs;
              }
              sel.startMs = start;
              sel.durationMs = end - start;
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'De ${clock(sel.startMs)} à ${clock(sel.endMs)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          _slider(
            icon: Icons.photo_size_select_large_rounded,
            label: 'Taille',
            value: sel.width,
            min: 0.1,
            max: 1,
            shown: '${(sel.width * 100).round()} %',
            onChanged: (v) => _edit(() => sel.width = v),
          ),
          _slider(
            icon: Icons.opacity_rounded,
            label: 'Opacité',
            value: sel.opacity,
            min: 0.1,
            max: 1,
            shown: '${(sel.opacity * 100).round()} %',
            onChanged: (v) => _edit(() => sel.opacity = v),
          ),
          if (!sel.isImage)
            _slider(
              icon: Icons.volume_up_rounded,
              label: 'Son',
              value: sel.volume,
              min: 0,
              max: 2,
              shown: '${(sel.volume * 100).round()} %',
              onChanged: (v) => _edit(() => sel.volume = v),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (label, x, y) in const [
                  ('Haut gauche', 0.2, 0.2),
                  ('Haut droite', 0.8, 0.2),
                  ('Centre', 0.5, 0.5),
                  ('Bas gauche', 0.2, 0.8),
                  ('Bas droite', 0.8, 0.8),
                ])
                  ActionChip(
                    label: Text(label),
                    onPressed: () => _edit(() {
                      sel.cx = x;
                      sel.cy = y;
                    }),
                  ),
                for (var lane = 0; lane < overlayLanes; lane++)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text('Piste ${lane + 1}'),
                    selected: sel.track == lane,
                    onSelected: (_) => _edit(() => sel.track = lane),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Placer à la lecture'),
                onPressed: () => _edit(() {
                  sel.startMs = math.min(
                    _playheadMs,
                    math.max(0, total - minClipMs),
                  );
                }),
              ),
              IconButton(
                tooltip: 'Dupliquer la couche',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => _edit(() {
                  overlays.add(sel.copy()..startMs = sel.endMs);
                  _selOverlay = overlays.length - 1;
                }),
              ),
              IconButton(
                tooltip: 'Supprimer la couche',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _edit(() {
                  overlays.remove(sel);
                  _selOverlay = -1;
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---- Sounds ----

  /// Copies a picked file to a real path the exporter can read.
  Future<String?> _realPath(PlatformFile file) async {
    final path = file.path;
    if (path != null) return path;
    final dir = Directory('${(await getTemporaryDirectory()).path}/montage');
    await dir.create(recursive: true);
    final copy = File(await uniquePath(dir.path, file.name));
    final sink = copy.openWrite();
    await sink.addStream(file.xFile.openRead());
    await sink.close();
    return copy.path;
  }

  Future<int> _probeAudioMs(String path) async {
    final probe = AudioPlayer();
    try {
      final d = await probe
          .setFilePath(path)
          .timeout(const Duration(seconds: 6));
      return d?.inMilliseconds ?? 0;
    } on Object {
      return 0;
    } finally {
      unawaited(probe.dispose());
    }
  }

  Future<void> _addSound() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.audio);
      if (file == null) return;
      final path = await _realPath(file);
      if (path == null || !mounted) return;
      final length = await _probeAudioMs(path);
      if (!mounted) return;
      _placeSound(path, file.name, length > 0 ? length : 30000, length);
    } on Object {
      if (mounted) showMessage(context, 'Impossible de lire ce fichier audio');
    }
  }

  void _placeSound(String path, String name, int length, int known) {
    final total = _project.totalMs;
    final start = math.min(_playheadMs, math.max(0, total - minClipMs));
    final duration = math.max(
      minClipMs,
      math.min(length, math.max(minClipMs, total - start)),
    );
    _edit(() {
      _project.sounds.add(
        AudioClip(
          path,
          name,
          startMs: start,
          durationMs: duration,
          sourceMs: known,
        ),
      );
      _selSound = _project.sounds.length - 1;
    });
  }

  /// Records the microphone while the preview plays, and lays the result on
  /// the timeline where the recording began.
  Future<void> _toggleVoice() async {
    final active = _recorder;
    if (active != null) {
      final path = await active.stop();
      final began = _voiceFrom;
      final elapsed = _voiceClock.elapsedMilliseconds;
      _voiceClock.stop();
      unawaited(active.dispose());
      _ui(() => _recorder = null);
      await _player?.pause();
      if (path == null || elapsed < minClipMs || !mounted) return;
      final total = _project.totalMs;
      _edit(() {
        _project.sounds.add(
          AudioClip(
            path,
            'Voix ${clock(began)}',
            startMs: began,
            durationMs: math.min(elapsed, math.max(minClipMs, total - began)),
            sourceMs: elapsed,
          ),
        );
        _selSound = _project.sounds.length - 1;
      });
      return;
    }
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) {
          showMessage(context, 'Autorisez le microphone pour enregistrer');
        }
        await recorder.dispose();
        return;
      }
      final dir = Directory('${(await getTemporaryDirectory()).path}/montage');
      await dir.create(recursive: true);
      final file =
          '${dir.path}/voix_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: file,
      );
      _voiceFrom = _playheadMs;
      _voiceClock
        ..reset()
        ..start();
      await _player?.play();
      _ui(() => _recorder = recorder);
    } on Object {
      await recorder.dispose();
      if (mounted) showMessage(context, "Enregistrement impossible");
    }
  }

  Widget _soundsSection() {
    final sounds = _project.sounds;
    final sel = _selSound >= 0 && _selSound < sounds.length
        ? sounds[_selSound]
        : null;
    final total = math.max(1, _project.totalMs);
    final recording = _recorder != null;
    return Column(
      children: [
        const Divider(height: 8),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter un son'),
                  onPressed: recording ? null : _addSound,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  style: recording
                      ? FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                        )
                      : null,
                  icon: Icon(
                    recording ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                  label: Text(recording ? 'Arrêter' : 'Enregistrer une voix'),
                  onPressed: _toggleVoice,
                ),
              ),
              for (final (i, a) in sounds.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.graphic_eq_rounded, size: 16),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: i == _selSound,
                    onSelected: (_) => _ui(() => _selSound = i),
                  ),
                ),
            ],
          ),
        ),
        if (sel != null) ...[
          RangeSlider(
            min: 0,
            max: total.toDouble(),
            values: RangeValues(
              sel.startMs.clamp(0, total).toDouble(),
              sel.endMs
                  .clamp(sel.startMs.clamp(0, total) + 1, total)
                  .toDouble(),
            ),
            onChanged: (v) => _edit(() {
              final start = v.start.round().clamp(0, total - minClipMs);
              var end = v.end.round().clamp(start + minClipMs, total);
              if (end - start > sel.maxDurationMs) {
                end = start + sel.maxDurationMs;
              }
              sel.startMs = start;
              sel.durationMs = end - start;
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '${sel.name} · de ${clock(sel.startMs)} à ${clock(sel.endMs)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          _slider(
            icon: Icons.volume_up_rounded,
            label: 'Volume',
            value: sel.volume,
            min: 0,
            max: 2,
            shown: '${(sel.volume * 100).round()} %',
            onChanged: (v) => _edit(() => sel.volume = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Placer à la lecture'),
                onPressed: () => _edit(() {
                  sel.startMs = math.min(
                    _playheadMs,
                    math.max(0, total - minClipMs),
                  );
                }),
              ),
              IconButton(
                tooltip: 'Supprimer le son',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _edit(() {
                  sounds.remove(sel);
                  _selSound = -1;
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---- Transitions ----

  Widget _transitionsPanel() {
    final c = _clip;
    final last = _selected == _project.clips.length - 1;
    final choices = last
        ? const [TransitionKind.none, TransitionKind.fade]
        : TransitionKind.values;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              last
                  ? 'Fin du montage'
                  : "Entre l'extrait ${_selected + 1} et le suivant",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in choices)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(
                    last && t == TransitionKind.fade
                        ? 'Fondu de fermeture'
                        : t.label,
                  ),
                  selected: c.transition == t,
                  onSelected: (_) => _edit(() => c.transition = t),
                ),
            ],
          ),
        ),
        if (c.transition != TransitionKind.none)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Durée', style: TextStyle(fontSize: 12)),
                for (final ms in const [300, 600, 1000, 1500])
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text('${formatNumber(ms / 1000)} s'),
                    selected: c.transitionMs == ms,
                    onSelected: (_) => _edit(() => c.transitionMs = ms),
                  ),
              ],
            ),
          ),
        if (c.transition != TransitionKind.none)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              "Le premier extrait sort, le suivant entre : l'effet se voit dans l'aperçu au début et à la fin de chaque extrait.",
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ),
        SwitchListTile(
          dense: true,
          title: const Text("Fondu d'ouverture"),
          subtitle: const Text('La vidéo apparaît depuis le noir'),
          value: _project.openingFade,
          onChanged: (v) => _edit(() => _project.openingFade = v),
        ),
      ],
    );
  }

  // ---- Cut a passage out of a clip ----

  /// Section of the trim panel: remove a passage from the middle.
  Widget _cutSection() {
    final c = _clip;
    if (c.isImage) return const SizedBox.shrink();
    final from = (_cutFrom >= c.startMs && _cutFrom < c.endMs)
        ? _cutFrom
        : c.startMs + c.keptMs ~/ 3;
    final to = (_cutTo > from && _cutTo <= c.endMs)
        ? _cutTo
        : c.startMs + 2 * c.keptMs ~/ 3;
    return Column(
      children: [
        const Divider(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Retirer un passage du milieu',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        RangeSlider(
          min: c.startMs.toDouble(),
          max: c.endMs.toDouble(),
          values: RangeValues(from.toDouble(), to.toDouble()),
          onChanged: (v) {
            final moved = v.start.round() != from;
            _ui(() {
              _cutFrom = v.start.round();
              _cutTo = v.end.round();
            });
            _seekTo(moved ? _cutFrom : _cutTo);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                'De ${clock(from)} à ${clock(to)} · ${clock(to - from)} retirés',
                style: const TextStyle(fontSize: 12),
              ),
              Wrap(
                spacing: 6,
                children: [
                  OutlinedButton(
                    onPressed: _player == null
                        ? null
                        : () => _ui(() {
                            _cutFrom = _player!.value.position.inMilliseconds;
                            if (_cutTo <= _cutFrom) _cutTo = c.endMs;
                          }),
                    child: const Text('Début ici'),
                  ),
                  OutlinedButton(
                    onPressed: _player == null
                        ? null
                        : () => _ui(() {
                            _cutTo = _player!.value.position.inMilliseconds;
                            if (_cutFrom >= _cutTo) _cutFrom = c.startMs;
                          }),
                    child: const Text('Fin ici'),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.content_cut_rounded),
                    label: const Text('Retirer'),
                    onPressed: () => _removePassage(from, to),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _removePassage(int from, int to) {
    final index = _selected;
    var done = false;
    _edit(() {
      done = _project.cutOut(index, from, to);
      if (done) {
        _cutFrom = -1;
        _cutTo = -1;
      }
    });
    if (done) {
      unawaited(_openPreview());
      showMessage(context, 'Passage retiré');
    } else {
      showMessage(
        context,
        'Ce passage est trop court, ou il ne resterait rien',
      );
    }
  }

  /// Duration of an image clip.
  Widget _imageDurationPanel() {
    final c = _clip;
    return Column(
      children: [
        _slider(
          icon: Icons.timer_outlined,
          label: 'Durée',
          value: c.keptMs / 1000,
          min: 1,
          max: 20,
          shown: '${formatNumber(c.keptMs / 1000)} s',
          onChanged: (v) => _edit(() => c.endMs = (v * 1000).round()),
        ),
        const Text(
          'Une image reste affichée pendant ce temps.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }
}
