import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../core/theme.dart';
import '../files/files_ui.dart';
import '../gallery/media_library.dart';
import 'edit_model.dart';
import 'edit_render.dart';

enum _Tab {
  adjust('Ajuster', Icons.tune_rounded),
  filters('Filtres', Icons.auto_awesome_rounded),
  crop('Rogner', Icons.crop_rounded),
  draw('Dessiner', Icons.brush_rounded);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _adjustIcons = <Adjust, IconData>{
  Adjust.brightness: Icons.brightness_6_rounded,
  Adjust.contrast: Icons.contrast_rounded,
  Adjust.saturation: Icons.water_drop_outlined,
  Adjust.warmth: Icons.thermostat_rounded,
  Adjust.fade: Icons.blur_on_rounded,
  Adjust.vignette: Icons.vignette_rounded,
};

const _penColors = <int>[
  0xFFFFFFFF,
  0xFF000000,
  0xFFE5484D,
  0xFFF76B15,
  0xFFFFC53D,
  0xFF30A46C,
  0xFF0A84FF,
  0xFF8E4EC6,
  0xFFD6409F,
];

/// Non-destructive photo editor. Edits are kept as a list of settings and
/// only applied to a new file when saved; the original is never changed.
class PhotoEditorPage extends StatefulWidget {
  const PhotoEditorPage({super.key, required this.path, this.outputDir});
  final String path;

  /// Where copies are saved; the Pictures folder when null.
  final String? outputDir;

  @override
  State<PhotoEditorPage> createState() => _PhotoEditorPageState();
}

class _PhotoEditorPageState extends State<PhotoEditorPage> {
  ui.Image? _image;
  String? _error;

  EditState _state = const EditState();
  final _undo = <EditState>[];
  final _redo = <EditState>[];
  EditState? _gestureStart;

  _Tab _tab = _Tab.adjust;
  Adjust _adjust = Adjust.brightness;
  CropRatio _ratio = cropRatios.first;
  int _penColor = _penColors[2];
  double _penWidth = 6;
  bool _comparing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // 1600 px is sharp on any phone screen and quick to repaint.
      final image = await loadPhoto(widget.path, maxSide: 1600);
      if (mounted) {
        setState(() => _image = image);
      } else {
        image.dispose();
      }
    } on Object {
      if (mounted) setState(() => _error = 'Impossible de lire cette image');
    }
  }

  bool get _changed => !_state.isUntouched;

  void _begin() => _gestureStart = _state;

  /// Closes a gesture: one undo step for everything done since [_begin].
  void _end() {
    final before = _gestureStart;
    _gestureStart = null;
    if (before != null) {
      _undo.add(before);
      _redo.clear();
    }
    setState(() {});
  }

  /// A change made in one go, such as a rotation or a filter choice.
  void _apply(EditState next) {
    setState(() {
      _undo.add(_state);
      _redo.clear();
      _state = next;
    });
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_state);
      _state = _undo.removeLast();
    });
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_state);
      _state = _redo.removeLast();
    });
  }

  Size get _oriented {
    final image = _image!;
    return orientedSize(
      image.width.toDouble(),
      image.height.toDouble(),
      _state,
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_changed || _saving) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text("Les changements non enregistrés seront perdus."),
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
    return leave == true;
  }

  Future<void> _save() async {
    final library = context.read<MediaLibrary>();
    final messenger = ScaffoldMessenger.of(context);
    var dir = widget.outputDir;
    if (dir == null) {
      if (!await ensureFullFileAccess(context)) return;
      dir = defaultOutputDir;
    }
    setState(() => _saving = true);
    try {
      final saved = await saveEditedCopy(widget.path, _state, dir: dir);
      await MediaChannel.rescan([saved]);
      unawaited(library.load(request: false));
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Saved: nothing left to lose when leaving.
        _undo.clear();
        _redo.clear();
        _state = const EditState();
      });
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('Copie enregistrée dans Images / All-in-One'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Partager',
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(files: [XFile(saved)])),
            ),
          ),
        );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, "L'enregistrement a échoué");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return PopScope(
      canPop: !_changed || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Theme(
        // The editor is always dark so colours are judged against neutral grey.
        data: buildTheme(
          Theme.of(context).colorScheme.primary,
          Brightness.dark,
        ),
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
              actions: [
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
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 12),
                  child: FilledButton(
                    onPressed: image == null || !_changed || _saving
                        ? null
                        : _save,
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
            body: _error != null
                ? Center(child: Text(_error!))
                : image == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (_saving) const LinearProgressIndicator(minHeight: 2),
                      Expanded(child: _canvas(image)),
                      _panel(image),
                      NavigationBar(
                        backgroundColor: const Color(0xFF17171C),
                        selectedIndex: _tab.index,
                        onDestinationSelected: (i) =>
                            setState(() => _tab = _Tab.values[i]),
                        destinations: [
                          for (final t in _Tab.values)
                            NavigationDestination(
                              icon: Icon(t.icon),
                              label: t.label,
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Photo area. Cropping and drawing work on the whole picture; the other
  /// tabs show the cropped result.
  Widget _canvas(ui.Image image) {
    final showFull = _tab == _Tab.crop || _tab == _Tab.draw;
    final shown = _comparing ? const EditState() : _state;
    final size = outputSize(image, shown, applyCrop: !showFull);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: GestureDetector(
            // Hold to compare with the original.
            onLongPressStart: showFull && _tab == _Tab.draw
                ? null
                : (_) => setState(() => _comparing = true),
            onLongPressEnd: (_) => setState(() => _comparing = false),
            child: LayoutBuilder(
              builder: (context, box) {
                final paint = CustomPaint(
                  size: box.biggest,
                  painter: EditPainter(image, shown, applyCrop: !showFull),
                );
                return switch (_tab) {
                  _Tab.crop => _CropOverlay(
                    crop: _state.crop,
                    ratio: _kForRatio(),
                    onStart: _begin,
                    onChanged: (r) =>
                        setState(() => _state = _state.copyWith(crop: r)),
                    onEnd: _end,
                    child: paint,
                  ),
                  _Tab.draw => _DrawLayer(
                    onStart: (p) {
                      _begin();
                      setState(() {
                        _state = _state.copyWith(
                          strokes: [
                            ..._state.strokes,
                            Stroke(_penColor, _penWidth * 0.002, [p]),
                          ],
                        );
                      });
                    },
                    onMove: (p) => setState(() {
                      final strokes = [..._state.strokes];
                      strokes[strokes.length - 1] = strokes.last.withPoint(p);
                      _state = _state.copyWith(strokes: strokes);
                    }),
                    onEnd: _end,
                    child: paint,
                  ),
                  _ => paint,
                };
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Normalised width over height to keep while cropping, or null if free.
  double? _kForRatio() {
    final ratio = _ratio.ratio;
    if (ratio == null) return null;
    final o = _oriented;
    return (ratio == 0 ? o.width / o.height : ratio) * o.height / o.width;
  }

  Widget _panel(ui.Image image) {
    return Container(
      height: 148,
      color: const Color(0xFF17171C),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: switch (_tab) {
        _Tab.adjust => _adjustPanel(),
        _Tab.filters => _filtersPanel(image),
        _Tab.crop => _cropPanel(),
        _Tab.draw => _drawPanel(),
      },
    );
  }

  Widget _adjustPanel() {
    final value = _state.value(_adjust);
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final a in Adjust.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(_adjustIcons[a], size: 18),
                    label: Text(a.label),
                    selected: a == _adjust,
                    onSelected: (_) => setState(() => _adjust = a),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                min: _adjust.min,
                max: _adjust.max,
                value: value.clamp(_adjust.min, _adjust.max),
                onChangeStart: (_) => _begin(),
                onChanged: (v) => setState(
                  () => _state = _state.withAdjust(_adjust, v.roundToDouble()),
                ),
                onChangeEnd: (_) => _end(),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${value.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Remettre à zéro',
              icon: const Icon(Icons.restart_alt_rounded, size: 20),
              onPressed: value == 0
                  ? null
                  : () => _apply(_state.withAdjust(_adjust, 0)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filtersPanel(ui.Image image) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: photoFilters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final f = photoFilters[i];
              final selected = f.id == _state.filter;
              return GestureDetector(
                onTap: () =>
                    _apply(_state.copyWith(filter: f.id, intensity: 1)),
                child: Column(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
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
                        child: CustomPaint(painter: _FilterThumb(image, f)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      f.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 36,
          child: _state.filter == 'none'
              ? const Center(
                  child: Text(
                    'Choisissez un filtre',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              : Row(
                  children: [
                    const SizedBox(width: 20),
                    const Text('Intensité', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _state.intensity,
                        onChangeStart: (_) => _begin(),
                        onChanged: (v) => setState(
                          () => _state = _state.copyWith(intensity: v),
                        ),
                        onChangeEnd: (_) => _end(),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(_state.intensity * 100).round()}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  void _setRatio(CropRatio r) {
    setState(() => _ratio = r);
    final ratio = r.ratio;
    if (ratio != null) {
      _apply(_state.copyWith(crop: centeredCrop(ratio, _oriented)));
    }
  }

  Widget _cropPanel() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final r in cropRatios)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Text(r.label),
                    selected: r == _ratio,
                    onSelected: (_) => _setRatio(r),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Pivoter à gauche',
                icon: const Icon(Icons.rotate_left_rounded),
                onPressed: () => _apply(_state.rotatedCounterClockwise()),
              ),
              IconButton(
                tooltip: 'Pivoter à droite',
                icon: const Icon(Icons.rotate_right_rounded),
                onPressed: () => _apply(_state.rotatedClockwise()),
              ),
              IconButton(
                tooltip: 'Miroir',
                icon: const Icon(Icons.flip_rounded),
                onPressed: () => _apply(_state.mirrored()),
              ),
              TextButton(
                onPressed: _state.isCropped
                    ? () {
                        setState(() => _ratio = cropRatios.first);
                        _apply(
                          _state.copyWith(
                            crop: const Rect.fromLTWH(0, 0, 1, 1),
                          ),
                        );
                      }
                    : null,
                child: const Text('Tout afficher'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _drawPanel() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final c in _penColors)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _penColor = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: _penColor == c ? 3 : 1,
                          color: _penColor == c
                              ? Colors.white54
                              : Colors.white24,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.line_weight_rounded, size: 20),
            Expanded(
              child: Slider(
                min: 2,
                max: 20,
                value: _penWidth,
                onChanged: (v) => setState(() => _penWidth = v),
              ),
            ),
            TextButton(
              onPressed: _state.strokes.isEmpty
                  ? null
                  : () => _apply(_state.copyWith(strokes: const [])),
              child: const Text('Tout effacer'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ],
    );
  }
}

/// Small square preview of a filter, cropped from the centre of the photo.
class _FilterThumb extends CustomPainter {
  _FilterThumb(this.image, this.filter);
  final ui.Image image;
  final PhotoFilter filter;

  @override
  void paint(Canvas canvas, Size size) {
    final side = image.width < image.height ? image.width : image.height;
    final src = Rect.fromCenter(
      center: Offset(image.width / 2, image.height / 2),
      width: side.toDouble(),
      height: side.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = filter.id == 'none'
            ? null
            : ColorFilter.matrix(filter.matrix),
    );
  }

  @override
  bool shouldRepaint(_FilterThumb old) =>
      old.image != image || old.filter != filter;
}

/// Collects drawing gestures as points from 0 to 1 over its child.
class _DrawLayer extends StatelessWidget {
  const _DrawLayer({
    required this.child,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  final Widget child;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        Offset norm(Offset p) => Offset(
          (p.dx / box.maxWidth).clamp(0.0, 1.0),
          (p.dy / box.maxHeight).clamp(0.0, 1.0),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onStart(norm(d.localPosition)),
          onPanUpdate: (d) => onMove(norm(d.localPosition)),
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: child,
        );
      },
    );
  }
}

enum _Handle { topLeft, topRight, bottomLeft, bottomRight, move }

/// Crop frame with draggable corners over the whole picture.
class _CropOverlay extends StatefulWidget {
  const _CropOverlay({
    required this.crop,
    required this.ratio,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    required this.child,
  });

  final Rect crop;

  /// Normalised width over height to keep, or null when free.
  final double? ratio;
  final VoidCallback onStart;
  final ValueChanged<Rect> onChanged;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  _Handle? _handle;

  _Handle? _hit(Offset p, Size size) {
    final r = widget.crop;
    final corners = {
      _Handle.topLeft: r.topLeft,
      _Handle.topRight: r.topRight,
      _Handle.bottomLeft: r.bottomLeft,
      _Handle.bottomRight: r.bottomRight,
    };
    _Handle? best;
    var bestDistance = 40.0; // generous: fingers are not precise
    corners.forEach((handle, corner) {
      final d = (Offset(corner.dx * size.width, corner.dy * size.height) - p)
          .distance;
      if (d < bestDistance) {
        best = handle;
        bestDistance = d;
      }
    });
    if (best != null) return best;
    final inside = Rect.fromLTRB(
      r.left * size.width,
      r.top * size.height,
      r.right * size.width,
      r.bottom * size.height,
    ).contains(p);
    return inside ? _Handle.move : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        Offset norm(Offset p) => Offset(p.dx / size.width, p.dy / size.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            _handle = _hit(d.localPosition, size);
            if (_handle != null) widget.onStart();
          },
          onPanUpdate: (d) {
            final handle = _handle;
            if (handle == null) return;
            final r = widget.crop;
            if (handle == _Handle.move) {
              widget.onChanged(
                moveWithin(
                  r,
                  Offset(d.delta.dx / size.width, d.delta.dy / size.height),
                ),
              );
              return;
            }
            final anchor = switch (handle) {
              _Handle.topLeft => r.bottomRight,
              _Handle.topRight => r.bottomLeft,
              _Handle.bottomLeft => r.topRight,
              _ => r.topLeft,
            };
            widget.onChanged(
              dragCorner(anchor, norm(d.localPosition), widget.ratio),
            );
          },
          onPanEnd: (_) {
            if (_handle != null) widget.onEnd();
            _handle = null;
          },
          child: CustomPaint(
            foregroundPainter: _CropPainter(
              widget.crop,
              Theme.of(context).colorScheme.primary,
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.crop, this.accent);
  final Rect crop;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    // Dim everything outside the frame.
    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addRect(r)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = const Color(0xA6000000),
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, line);
    // Rule-of-thirds guides.
    final thin = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(r.left + r.width * i / 3, r.top),
        Offset(r.left + r.width * i / 3, r.bottom),
        thin,
      );
      canvas.drawLine(
        Offset(r.left, r.top + r.height * i / 3),
        Offset(r.right, r.top + r.height * i / 3),
        thin,
      );
    }
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    const len = 20.0;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(dx * len, 0), corner);
      canvas.drawLine(c, c + Offset(0, dy * len), corner);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}
