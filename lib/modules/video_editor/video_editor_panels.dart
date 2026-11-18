part of 'video_editor_page.dart';

/// The side panels: the settings of a tool, next to the preview.
extension _Panels on _VideoEditorPageState {
  static const _titleColors = [
    0xFFFFFFFF,
    0xFFFFD60A,
    0xFFFF453A,
    0xFF30D158,
    0xFF0A84FF,
    0xFFBF5AF2,
    0xFF000000,
  ];

  String get _panelTitle => switch (_panel!) {
    _Panel.speed => 'Vitesse',
    _Panel.volume => 'Volume',
    _Panel.filters => 'Filtres',
    _Panel.adjust => 'Ajuster',
    _Panel.effects => 'Effets',
    _Panel.transition => 'Transition',
    _Panel.format => 'Format',
    _Panel.audio => 'Audio',
    _Panel.overlay => 'Incrustation',
    _Panel.textStyle => 'Style du texte',
    _Panel.sound => 'Son',
    _Panel.segment => 'Retirer un segment',
  };

  Widget _panelView() {
    return SizedBox(
      width: 290,
      child: Material(
        color: _surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _panelTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer le panneau',
                    icon: const Icon(Icons.check_rounded),
                    onPressed: () => _ui(() => _panel = null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('panel-scroll'),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                child: _panelBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelBody() => switch (_panel!) {
    _Panel.speed => _speedBody(),
    _Panel.volume => _volumeBody(),
    _Panel.filters => _filtersBody(),
    _Panel.adjust => _adjustBody(),
    _Panel.effects => _effectsBody(),
    _Panel.transition => _transitionBody(),
    _Panel.format => _formatBody(),
    _Panel.audio => _audioBody(),
    _Panel.overlay => _overlayBody(),
    _Panel.textStyle => _textStyleBody(),
    _Panel.sound => _soundBody(),
    _Panel.segment => _segmentBody(),
  };

  // ---- Small building blocks ----

  Widget _param({
    required String label,
    required String shown,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            Text(
              shown,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          semanticFormatterCallback: (_) => '$label $shown',
          value: value.clamp(min, max),
          onChanged: (v) {
            _merge = true;
            onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _chips<T>({
    required Iterable<T> values,
    required String Function(T) label,
    required bool Function(T) selected,
    required ValueChanged<T> onSelect,
    bool Function(T)? enabled,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final v in values)
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: Text(label(v)),
            selected: selected(v),
            onSelected: (enabled?.call(v) ?? true) ? (_) => onSelect(v) : null,
          ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.white54,
      ),
    ),
  );

  Widget _none(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: const TextStyle(fontSize: 12, color: Colors.white70),
    ),
  );

  // ---- Speed ----

  /// Slider value (0–1) ↔ speed, on a logarithmic scale.
  double _speedToSlider(double s) =>
      (math.log(s / minSpeed) / math.log(maxSpeed / minSpeed)).clamp(0.0, 1.0);
  double _sliderToSpeed(double v) {
    final s = minSpeed * math.pow(maxSpeed / minSpeed, v);
    // Snaps to hundredths so the value reads cleanly.
    return (s * 20).round() / 20;
  }

  Widget _speedBody() {
    final c = _clip;
    if (c == null) return _none('Sélectionnez un extrait.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chips<double>(
          values: speedChoices,
          label: (s) => '${formatNumber(s)}×',
          selected: (s) => (c.speed - s).abs() < 0.001,
          onSelect: (s) => _edit(() => c.speed = s),
        ),
        const SizedBox(height: 6),
        _param(
          label: 'Vitesse personnalisée',
          shown: '${formatNumber(c.speed)}×',
          value: _speedToSlider(c.speed),
          min: 0,
          max: 1,
          onChanged: (v) => _edit(
            () => c.speed = _sliderToSpeed(v).clamp(minSpeed, maxSpeed),
          ),
        ),
        Text(
          'Cet extrait dure ${clock(c.outputMs)} après ce réglage.',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  // ---- Volume ----

  Widget _volumeBody() {
    final c = _clip;
    if (c == null) return _none('Sélectionnez un extrait.');
    final silenced = _project.muteOriginal || _project.musicPath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _param(
          label: 'Volume de cet extrait',
          shown: '${(c.volume * 100).round()} %',
          value: c.volume,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => _edit(() => c.volume = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(c.volume == 0 ? Icons.volume_up : Icons.volume_off),
            label: Text(c.volume == 0 ? 'Rétablir le son' : 'Couper le son'),
            onPressed: () => _edit(() => c.volume = c.volume == 0 ? 1 : 0),
          ),
        ),
        if (silenced)
          _none(
            _project.musicPath != null
                ? "Une musique est ajoutée : elle remplace le son d'origine."
                : "Le son d'origine est coupé pour tout le montage.",
          ),
      ],
    );
  }

  // ---- Filters and adjustments ----

  Widget _filtersBody() {
    final c = _clip;
    if (c == null) return _none('Sélectionnez un extrait.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in VideoFilter.values)
              Semantics(
                button: true,
                selected: c.filter == f,
                label: 'Filtre ${f.label}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _edit(() => c.filter = f),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(f.swatch),
                                Color(f.swatch).withValues(alpha: 0.45),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              width: c.filter == f ? 3 : 1,
                              color: c.filter == f
                                  ? Colors.white
                                  : Colors.white24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          f.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.done_all_rounded),
            label: const Text('Appliquer à tous'),
            onPressed: () {
              _edit(() {
                for (final o in _project.clips) {
                  o
                    ..filter = c.filter
                    ..brightness = c.brightness
                    ..contrastAdjust = c.contrastAdjust
                    ..saturationAdjust = c.saturationAdjust;
                }
              });
              showMessage(context, 'Look appliqué à tous les extraits');
            },
          ),
        ),
      ],
    );
  }

  Widget _adjustBody() {
    final c = _clip;
    if (c == null) return _none('Sélectionnez un extrait.');
    return Column(
      children: [
        _param(
          label: 'Luminosité',
          shown: '${((c.brightness - 1) * 100).round()}',
          value: c.brightness,
          min: 0.5,
          max: 1.5,
          onChanged: (v) => _edit(() => c.brightness = v),
        ),
        _param(
          label: 'Contraste',
          shown: '${(c.contrastAdjust * 200).round()}',
          value: c.contrastAdjust,
          min: -0.5,
          max: 0.5,
          onChanged: (v) => _edit(() => c.contrastAdjust = v),
        ),
        _param(
          label: 'Saturation',
          shown: '${((c.saturationAdjust - 1) * 100).round()}',
          value: c.saturationAdjust,
          min: 0,
          max: 2,
          onChanged: (v) => _edit(() => c.saturationAdjust = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Réinitialiser'),
            onPressed: () => _edit(c.resetLook),
          ),
        ),
      ],
    );
  }

  // ---- Effects ----

  Widget _effectsBody() {
    final c = _clip;
    if (c == null) return _none('Sélectionnez un extrait.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chips<ClipEffect>(
          values: ClipEffect.values,
          label: (e) => e.label,
          selected: (e) => c.effect == e,
          onSelect: (e) => _edit(() => c.effect = e),
        ),
        _param(
          label: 'Flou',
          shown: '${(c.blur * 100).round()} %',
          value: c.blur,
          min: 0,
          max: 1,
          onChanged: (v) => _edit(() => c.blur = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Miroir'),
          value: c.flip,
          onChanged: (v) => _edit(() => c.flip = v),
        ),
      ],
    );
  }

  // ---- Transition ----

  Widget _transitionBody() {
    final c = _clip;
    if (c == null) return _none('Sélectionnez un extrait.');
    final last = _sel.index == _project.clips.length - 1;
    final choices = last
        ? const [TransitionKind.none, TransitionKind.fade]
        : TransitionKind.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          last
              ? 'Fin du montage'
              : "Entre l'extrait ${_sel.index + 1} et le suivant",
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        _chips<TransitionKind>(
          values: choices,
          label: (t) =>
              last && t == TransitionKind.fade ? 'Fondu de fermeture' : t.label,
          selected: (t) => c.transition == t,
          onSelect: (t) => _edit(() => c.transition = t),
        ),
        if (c.transition != TransitionKind.none) ...[
          _section('DURÉE'),
          _chips<int>(
            values: const [300, 600, 1000, 1500],
            label: (ms) => '${formatNumber(ms / 1000)} s',
            selected: (ms) => c.transitionMs == ms,
            onSelect: (ms) => _edit(() => c.transitionMs = ms),
          ),
        ],
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text("Fondu d'ouverture"),
          subtitle: const Text('Depuis le noir, au début'),
          value: _project.openingFade,
          onChanged: (v) => _edit(() => _project.openingFade = v),
        ),
      ],
    );
  }

  // ---- Format ----

  Widget _formatBody() {
    final size = _project.outputSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chips<Aspect>(
          values: Aspect.values,
          label: (a) => a.label,
          selected: (a) => _project.aspect == a,
          onSelect: (a) => _edit(() => _project.aspect = a),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Remplir le cadre'),
          subtitle: Text(
            _project.fillFrame
                ? 'Bords rognés'
                : 'Bandes noires, vidéo entière',
          ),
          value: _project.fillFrame,
          onChanged: (v) => _edit(() => _project.fillFrame = v),
        ),
        Text(
          'Vidéo finale : ${size.width.round()} × ${size.height.round()}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  // ---- Audio ----

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

  Future<void> _pickMusic() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.audio);
      if (file == null) return;
      final path = await _realPath(file);
      if (path == null || !mounted) return;
      _edit(() {
        _project
          ..musicPath = path
          ..musicName = file.name;
      });
    } on Object {
      if (mounted) showMessage(context, 'Impossible de lire ce fichier audio');
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
      final total = _project.totalMs;
      final start = math.min(_now, math.max(0, total - minClipMs));
      final known = length;
      final duration = math.max(
        minClipMs,
        math.min(known > 0 ? known : 30000, math.max(minClipMs, total - start)),
      );
      _edit(() {
        _project.sounds.add(
          AudioClip(
            path,
            file.name,
            startMs: start,
            durationMs: duration,
            sourceMs: known,
          ),
        );
        _sel = Selection(SelKind.sound, _project.sounds.length - 1);
        _panel = _Panel.sound;
      });
    } on Object {
      if (mounted) showMessage(context, 'Impossible de lire ce fichier audio');
    }
  }

  /// Records the microphone while the montage plays, and lays the result on
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
      _player.pause();
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
        _sel = Selection(SelKind.sound, _project.sounds.length - 1);
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
      _voiceFrom = _now;
      _voiceClock
        ..reset()
        ..start();
      unawaited(_player.play());
      _ui(() => _recorder = recorder);
    } on Object {
      await recorder.dispose();
      if (mounted) showMessage(context, 'Enregistrement impossible');
    }
  }

  Widget _audioBody() {
    final hasMusic = _project.musicPath != null;
    final recording = _recorder != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('MUSIQUE DE FOND'),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
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
        if (hasMusic)
          _param(
            label: 'Volume de la musique',
            shown: '${(_project.musicVolume * 100).round()} %',
            value: _project.musicVolume,
            min: 0,
            max: 2,
            divisions: 40,
            onChanged: (v) => _edit(() => _project.musicVolume = v),
          ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text("Couper le son d'origine"),
          subtitle: const Text('Pour tous les extraits'),
          value: _project.muteOriginal || hasMusic,
          onChanged: hasMusic
              ? null
              : (v) => _edit(() => _project.muteOriginal = v),
        ),
        _section('SONS SUR LA FRISE'),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un son'),
              onPressed: recording ? null : _addSound,
            ),
            FilledButton.tonalIcon(
              style: recording
                  ? FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    )
                  : null,
              icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
              label: Text(recording ? 'Arrêter' : 'Enregistrer une voix'),
              onPressed: _toggleVoice,
            ),
          ],
        ),
        _none(
          'Le son est placé à la tête de lecture ; faites-le glisser sur la frise pour le déplacer.',
        ),
      ],
    );
  }

  Widget _soundBody() {
    if (_sel.kind != SelKind.sound || _sel.index >= _project.sounds.length) {
      return _none('Sélectionnez un son sur la frise.');
    }
    final a = _project.sounds[_sel.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(
          'De ${clock(a.startMs)} à ${clock(a.endMs)}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        _param(
          label: 'Volume',
          shown: '${(a.volume * 100).round()} %',
          value: a.volume,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => _edit(() => a.volume = v),
        ),
      ],
    );
  }

  // ---- Overlay ----

  Widget _overlayBody() {
    if (_sel.kind != SelKind.overlay ||
        _sel.index >= _project.overlays.length) {
      return _none("Sélectionnez une incrustation sur la frise.");
    }
    final o = _project.overlays[_sel.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${o.media.name} · de ${clock(o.startMs)} à ${clock(o.endMs)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        _param(
          label: 'Taille',
          shown: '${(o.width * 100).round()} %',
          value: o.width,
          min: 0.1,
          max: 1,
          onChanged: (v) => _edit(() => o.width = v),
        ),
        _param(
          label: 'Opacité',
          shown: '${(o.opacity * 100).round()} %',
          value: o.opacity,
          min: 0.1,
          max: 1,
          onChanged: (v) => _edit(() => o.opacity = v),
        ),
        if (!o.isImage)
          _param(
            label: 'Son',
            shown: '${(o.volume * 100).round()} %',
            value: o.volume,
            min: 0,
            max: 2,
            divisions: 40,
            onChanged: (v) => _edit(() => o.volume = v),
          ),
        _section('POSITION'),
        Wrap(
          spacing: 6,
          children: [
            for (final (label, x, y) in const [
              ('Haut gauche', 0.2, 0.2),
              ('Haut droite', 0.8, 0.2),
              ('Centre', 0.5, 0.5),
              ('Bas gauche', 0.2, 0.8),
              ('Bas droite', 0.8, 0.8),
            ])
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(label),
                onPressed: () => _edit(() {
                  o.cx = x;
                  o.cy = y;
                }),
              ),
          ],
        ),
        _section('PISTE'),
        _chips<int>(
          values: List.generate(overlayLanes, (i) => i),
          label: (i) => 'Piste ${i + 1}',
          selected: (i) => o.track == i,
          onSelect: (i) => _edit(() => o.track = i),
        ),
        const SizedBox(height: 6),
        _none('Glissez l’incrustation dans l’aperçu pour la placer.'),
      ],
    );
  }

  // ---- Text style ----

  Widget _textStyleBody() {
    if (_sel.kind != SelKind.text || _sel.index >= _project.titles.length) {
      return _none('Sélectionnez un texte sur la frise.');
    }
    final t = _project.titles[_sel.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _param(
          label: 'Taille',
          shown: '${(t.size * 100).round()}',
          value: t.size,
          min: 0.03,
          max: 0.3,
          onChanged: (v) => _edit(() => t.size = v),
        ),
        _section('COULEUR'),
        Wrap(
          children: [
            for (final c in _titleColors)
              Semantics(
                label: 'Couleur du texte',
                button: true,
                child: GestureDetector(
                  onTap: () => _edit(() => t.color = c),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: t.color == c ? 3 : 1,
                          color: t.color == c ? Colors.white70 : Colors.white24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        _section('FOND'),
        _chips<TitleBox>(
          values: TitleBox.values,
          label: (b) => b.label,
          selected: (b) => t.box == b,
          onSelect: (b) => _edit(() => t.box = b),
        ),
        _section('ANIMATION'),
        _chips<TitleAnimation>(
          values: TitleAnimation.values,
          label: (a) => a.label,
          selected: (a) => t.animation == a,
          onSelect: (a) => _edit(() => t.animation = a),
        ),
        _section('POSITION'),
        Wrap(
          spacing: 6,
          children: [
            for (final (label, x, y) in const [
              ('Haut', 0.5, 0.1),
              ('Centre', 0.5, 0.5),
              ('Bas', 0.5, 0.9),
            ])
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(label),
                onPressed: () => _edit(() {
                  t.x = x;
                  t.y = y;
                }),
              ),
          ],
        ),
        _none("Glissez le texte dans l’aperçu pour le placer."),
      ],
    );
  }

  // ---- Remove a segment ----

  Widget _segmentBody() {
    final c = _clip;
    if (c == null || c.isImage) return _none('Sélectionnez un extrait vidéo.');
    final from = (_cutFrom >= c.startMs && _cutFrom < c.endMs)
        ? _cutFrom
        : c.startMs + c.keptMs ~/ 3;
    final to = (_cutTo > from && _cutTo <= c.endMs)
        ? _cutTo
        : c.startMs + 2 * c.keptMs ~/ 3;
    // The playhead, as a moment of the source video, when inside this clip.
    int? here;
    final (index, offset) = _project.locate(_now);
    if (index == _sel.index) here = c.startMs + (offset * c.speed).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _none(
          "Choisissez le passage à enlever : le reste se rejoint. (Vous pouvez aussi diviser deux fois, puis supprimer le morceau du milieu.)",
        ),
        RangeSlider(
          min: c.startMs.toDouble(),
          max: c.endMs.toDouble(),
          values: RangeValues(from.toDouble(), to.toDouble()),
          onChanged: (v) {
            _ui(() {
              _cutFrom = v.start.round();
              _cutTo = v.end.round();
            });
          },
        ),
        Text(
          'De ${clock(from)} à ${clock(to)} · ${clock(to - from)} retirés',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            OutlinedButton(
              onPressed: here == null
                  ? null
                  : () => _ui(() {
                      _cutFrom = here!;
                      if (_cutTo <= _cutFrom) _cutTo = c.endMs;
                    }),
              child: const Text('Début ici'),
            ),
            OutlinedButton(
              onPressed: here == null
                  ? null
                  : () => _ui(() {
                      _cutTo = here!;
                      if (_cutFrom >= _cutTo) _cutFrom = c.startMs;
                    }),
              child: const Text('Fin ici'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.content_cut_rounded),
              label: const Text('Retirer'),
              onPressed: () {
                final i = _sel.index;
                var done = false;
                _edit(() {
                  done = _project.cutOut(i, from, to);
                  if (done) {
                    _cutFrom = -1;
                    _cutTo = -1;
                  }
                });
                showMessage(
                  context,
                  done
                      ? 'Segment retiré'
                      : 'Ce passage est trop court, ou il ne resterait rien',
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
