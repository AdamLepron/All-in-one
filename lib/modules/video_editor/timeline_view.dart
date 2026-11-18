import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../gallery/media_grid.dart';
import 'video_project.dart';

/// What is selected on the timeline.
enum SelKind { none, clip, overlay, text, sound, music }

class Selection {
  const Selection(this.kind, [this.index = 0]);
  static const none = Selection(SelKind.none);

  final SelKind kind;
  final int index;

  bool get isNone => kind == SelKind.none;
  bool is_(SelKind k, int i) => kind == k && index == i;

  @override
  bool operator ==(Object other) =>
      other is Selection && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

/// Fewest and most pixels a millisecond may take on the timeline.
const minPxPerMs = 0.012;
const maxPxPerMs = 0.6;
const defaultPxPerMs = 0.08;

/// A bar on a lane of the timeline: an overlay, a text, a sound.
class _Bar {
  const _Bar({
    required this.sel,
    required this.start,
    required this.end,
    required this.label,
    required this.color,
    required this.icon,
    required this.setSpan,
    required this.maxLength,
  });

  final Selection sel;
  final int start;
  final int end;
  final String label;
  final Color color;
  final IconData icon;

  /// Moves or resizes the bar; given the new start and end.
  final void Function(int start, int end) setSpan;

  /// Longest the bar may be (milliseconds).
  final int maxLength;
}

/// The multitrack timeline, as in CapCut: the playhead stays in the middle
/// and the tracks slide under it. Drag to move through the montage, pinch
/// to zoom, tap a bar to select it, drag the handles of the selected bar to
/// trim it, or drag its body to move it.
class EditorTimeline extends StatefulWidget {
  const EditorTimeline({
    super.key,
    required this.project,
    required this.time,
    required this.selection,
    required this.pxPerMs,
    required this.onZoom,
    required this.onSeek,
    required this.onScrubStart,
    required this.onSelect,
    required this.onEdit,
    required this.onAddClip,
    required this.onTransition,
  });

  final VideoProject project;

  /// The playhead, in milliseconds.
  final ValueNotifier<int> time;
  final Selection selection;
  final double pxPerMs;
  final ValueChanged<double> onZoom;
  final ValueChanged<int> onSeek;
  final VoidCallback onScrubStart;
  final ValueChanged<Selection> onSelect;

  /// Runs a change of the montage (the page records it for undo and saves).
  final void Function(VoidCallback change) onEdit;
  final VoidCallback onAddClip;

  /// The little button between clip [i] and the next.
  final ValueChanged<int> onTransition;

  @override
  State<EditorTimeline> createState() => _EditorTimelineState();
}

class _EditorTimelineState extends State<EditorTimeline> {
  final ScrollController _scroll = ScrollController();
  bool _user = false;
  final Map<int, Offset> _pointers = {};
  double _pinchStart = 0;
  double _pinchZoom = 0;
  bool _pinching = false;

  static const _rulerHeight = 22.0;
  static const _mainHeight = 54.0;
  static const _barHeight = 26.0;
  static const _gap = 3.0;

  @override
  void initState() {
    super.initState();
    widget.time.addListener(_follow);
  }

  @override
  void didUpdateWidget(EditorTimeline old) {
    super.didUpdateWidget(old);
    if (old.time != widget.time) {
      old.time.removeListener(_follow);
      widget.time.addListener(_follow);
    }
    // Zooming or editing keeps the playhead on the same moment.
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void dispose() {
    widget.time.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  /// Moves the tracks so that the playhead is on the current time.
  void _follow() {
    if (_user || !_scroll.hasClients) return;
    final target = (widget.time.value * widget.pxPerMs).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((_scroll.offset - target).abs() > 0.5) _scroll.jumpTo(target);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _user = true;
      widget.onScrubStart();
    } else if (n is ScrollUpdateNotification && _user) {
      widget.onSeek((n.metrics.pixels / widget.pxPerMs).round());
    } else if (n is ScrollEndNotification) {
      _user = false;
    }
    return false;
  }

  // ---- Pinch to zoom ----

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinching = true;
      _pinchStart = _spread();
      _pinchZoom = widget.pxPerMs;
      setState(() {});
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pinching && _pointers.length >= 2 && _pinchStart > 10) {
      final scale = _spread() / _pinchStart;
      widget.onZoom((_pinchZoom * scale).clamp(minPxPerMs, maxPxPerMs));
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.length < 2) {
      _pinching = false;
      setState(() {});
    }
  }

  double _spread() {
    final p = _pointers.values.take(2).toList();
    return p.length < 2 ? 0 : (p[0] - p[1]).distance;
  }

  // ---- Building ----

  Color _tint(Color c, bool selected) =>
      selected ? c : c.withValues(alpha: 0.9);

  /// Bars of overlays, texts and sounds, grouped into lanes.
  List<List<_Bar>> _overlayLanes() {
    final p = widget.project;
    final lanes = <List<_Bar>>[];
    final tracks = {for (final o in p.overlays) o.track}.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final track in tracks) {
      final rows = <List<_Bar>>[];
      final items = [
        for (final (i, o) in p.overlays.indexed)
          if (o.track == track) (i, o),
      ]..sort((a, b) => a.$2.startMs.compareTo(b.$2.startMs));
      for (final (i, o) in items) {
        final bar = _Bar(
          sel: Selection(SelKind.overlay, i),
          start: o.startMs,
          end: o.endMs,
          label: o.media.name,
          color: const Color(0xFF00897B),
          icon: o.isImage ? Icons.image_outlined : Icons.videocam_outlined,
          setSpan: (s, e) {
            o.startMs = s;
            o.durationMs = e - s;
          },
          maxLength: o.maxDurationMs,
        );
        final row = rows.where((r) => r.last.end <= o.startMs).firstOrNull;
        if (row != null) {
          row.add(bar);
        } else {
          rows.add([bar]);
        }
      }
      lanes.addAll(rows);
    }
    return lanes;
  }

  List<List<_Bar>> _textLanes() {
    final p = widget.project;
    final rows = <List<_Bar>>[];
    final items = [for (final (i, t) in p.titles.indexed) (i, t)]
      ..sort((a, b) => a.$2.startMs.compareTo(b.$2.startMs));
    for (final (i, t) in items) {
      final bar = _Bar(
        sel: Selection(SelKind.text, i),
        start: t.startMs,
        end: t.endMs,
        label: t.text,
        color: const Color(0xFFEF6C00),
        icon: Icons.title_rounded,
        setSpan: (s, e) {
          t.startMs = s;
          t.endMs = e;
        },
        maxLength: 1 << 30,
      );
      final row = rows.where((r) => r.last.end <= t.startMs).firstOrNull;
      if (row != null) {
        row.add(bar);
      } else {
        rows.add([bar]);
      }
    }
    return rows;
  }

  List<List<_Bar>> _soundLanes() {
    final p = widget.project;
    final rows = <List<_Bar>>[];
    final items = [for (final (i, a) in p.sounds.indexed) (i, a)]
      ..sort((a, b) => a.$2.startMs.compareTo(b.$2.startMs));
    for (final (i, a) in items) {
      final bar = _Bar(
        sel: Selection(SelKind.sound, i),
        start: a.startMs,
        end: a.endMs,
        label: a.name,
        color: const Color(0xFFD81B60),
        icon: Icons.graphic_eq_rounded,
        setSpan: (s, e) {
          a.startMs = s;
          a.durationMs = e - s;
        },
        maxLength: a.maxDurationMs,
      );
      final row = rows.where((r) => r.last.end <= a.startMs).firstOrNull;
      if (row != null) {
        row.add(bar);
      } else {
        rows.add([bar]);
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final total = math.max(1, p.totalMs);
    final k = widget.pxPerMs;
    return LayoutBuilder(
      builder: (context, box) {
        final pad = box.maxWidth / 2;
        final contentWidth = total * k + box.maxWidth;
        final overlayRows = _overlayLanes();
        final textRows = _textLanes();
        final soundRows = _soundLanes();
        final hasMusic = p.musicPath != null;

        Widget lane(List<_Bar> bars) => SizedBox(
          height: _barHeight + _gap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [for (final b in bars) _barWidget(b, pad, total)],
          ),
        );

        final tracks = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in overlayRows) lane(row),
            for (final row in textRows) lane(row),
            _mainTrack(pad, total),
            if (hasMusic)
              lane([
                _Bar(
                  sel: const Selection(SelKind.music),
                  start: 0,
                  end: total,
                  label: p.musicName ?? 'Musique',
                  color: const Color(0xFF8E24AA),
                  icon: Icons.music_note_rounded,
                  setSpan: (_, _) {},
                  maxLength: total,
                ),
              ]),
            for (final row in soundRows) lane(row),
            const SizedBox(height: 40),
          ],
        );

        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: _pinching
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: contentWidth,
                    height: box.maxHeight,
                    child: Column(
                      children: [
                        CustomPaint(
                          size: Size(contentWidth, _rulerHeight),
                          painter: _RulerPainter(
                            pxPerMs: k,
                            totalMs: total,
                            pad: pad,
                            color: Colors.white54,
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (_, area) => SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: area.maxHeight,
                                  minWidth: contentWidth,
                                ),
                                // Tapping the empty background deselects.
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onSelect(Selection.none),
                                  child: SizedBox(
                                    width: contentWidth,
                                    child: tracks,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Adding a clip: always within reach, at the right of the main track.
              Positioned(
                right: 6,
                top:
                    _rulerHeight +
                    (overlayRows.length + textRows.length) *
                        (_barHeight + _gap) +
                    4 +
                    (_mainHeight - 36) / 2,
                width: 36,
                height: 36,
                child: Semantics(
                  button: true,
                  label: 'Ajouter un extrait',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('add-clip'),
                    onTap: widget.onAddClip,
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.black),
                    ),
                  ),
                ),
              ),
              // The playhead stays in the middle.
              Positioned(
                left: pad - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: const IgnorePointer(
                  child: ColoredBox(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Main track ----

  Widget _mainTrack(double pad, int total) {
    final p = widget.project;
    final k = widget.pxPerMs;
    return SizedBox(
      height: _mainHeight + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (i, c) in p.clips.indexed)
            Positioned(
              left: pad + p.startOf(i) * k,
              top: 4,
              width: math.max(10.0, c.outputMs * k),
              height: _mainHeight,
              child: _clipTile(i, c),
            ),
          // Buttons for the hand-over between two clips.
          for (var i = 0; i < p.clips.length - 1; i++)
            Positioned(
              left: pad + p.startOf(i + 1) * k - 13,
              top: 4 + _mainHeight / 2 - 13,
              width: 26,
              height: 26,
              child: Semantics(
                button: true,
                label: 'Transition entre les extraits ${i + 1} et ${i + 2}',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('join-$i'),
                  onTap: () => widget.onTransition(i),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.clips[i].transition == TransitionKind.none
                          ? const Color(0xFF2A2A31)
                          : Theme.of(context).colorScheme.primary,
                      border: Border.all(color: Colors.white54),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      size: 16,
                      color: p.clips[i].transition == TransitionKind.none
                          ? Colors.white70
                          : Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _clipTile(int i, VideoClip c) {
    final selected = widget.selection.is_(SelKind.clip, i);
    final k = widget.pxPerMs;
    final width = math.max(10.0, c.outputMs * k);
    final tiles = math.max(1, math.min(12, (width / 56).ceil()));
    return Semantics(
      button: true,
      selected: selected,
      label: 'Extrait ${i + 1}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('clip-$i'),
        onTap: () => widget.onSelect(Selection(SelKind.clip, i)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: [
                        for (var t = 0; t < tiles; t++)
                          Expanded(
                            child: MediaThumb(c.media, showDuration: false),
                          ),
                      ],
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          '${clock(c.outputMs)}${c.speed != 1 ? ' · ${_speedText(c.speed)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    if (c.styled || c.volume != 1)
                      const Positioned(
                        top: 2,
                        left: 3,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (selected) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
              _handle(
                key: ValueKey('trim-start-$i'),
                left: true,
                onDelta: (dMs) => widget.onEdit(() {
                  c.setStart(c.startMs + (dMs * c.speed).round());
                }),
              ),
              _handle(
                key: ValueKey('trim-end-$i'),
                left: false,
                onDelta: (dMs) => widget.onEdit(() {
                  c.setEnd(c.endMs + (dMs * c.speed).round());
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A white grip on a side of the selected bar; dragging it trims.
  Widget _handle({
    required Key key,
    required bool left,
    required ValueChanged<double> onDelta,
  }) {
    return Positioned(
      left: left ? -2 : null,
      right: left ? null : -2,
      top: 0,
      bottom: 0,
      width: 16,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => widget.onScrubStart(),
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx / widget.pxPerMs),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(left ? 6 : 0),
              right: Radius.circular(left ? 0 : 6),
            ),
          ),
          alignment: Alignment.center,
          child: Container(width: 2, height: 14, color: Colors.black45),
        ),
      ),
    );
  }

  String _speedText(double s) => '${s == s.roundToDouble() ? s.round() : s}×';

  // ---- Overlay, text and sound bars ----

  Widget _barWidget(_Bar b, double pad, int total) {
    final k = widget.pxPerMs;
    final selected = widget.selection == b.sel;
    final width = math.max(14.0, (b.end - b.start) * k);

    void move(double dMs) {
      widget.onEdit(() {
        final len = b.end - b.start;
        final s = (b.start + dMs.round())
            .clamp(0, math.max(0, total - len))
            .toInt();
        b.setSpan(s, s + len);
      });
    }

    void resize({required bool startSide, required double dMs}) {
      widget.onEdit(() {
        var s = b.start, e = b.end;
        if (startSide) {
          s = (s + dMs.round()).clamp(
            math.max(0, e - b.maxLength),
            e - minClipMs,
          );
        } else {
          e = (e + dMs.round()).clamp(
            s + minClipMs,
            math.min(total, s + b.maxLength),
          );
        }
        b.setSpan(s, e);
      });
    }

    return Positioned(
      left: pad + b.start * k,
      top: 0,
      width: width,
      height: _barHeight,
      child: Semantics(
        button: true,
        selected: selected,
        label: b.label,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('bar-${b.sel.kind.name}-${b.sel.index}'),
          onTap: () => widget.onSelect(b.sel),
          // Only the selected bar is dragged; the others scroll the tracks.
          onHorizontalDragStart: selected ? (_) => widget.onScrubStart() : null,
          onHorizontalDragUpdate: selected ? (d) => move(d.delta.dx / k) : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: _tint(b.color, selected),
                    borderRadius: BorderRadius.circular(6),
                    border: selected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(b.icon, size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          b.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selected && b.sel.kind != SelKind.music) ...[
                _handle(
                  key: ValueKey('bar-start-${b.sel.kind.name}-${b.sel.index}'),
                  left: true,
                  onDelta: (d) => resize(startSide: true, dMs: d),
                ),
                _handle(
                  key: ValueKey('bar-end-${b.sel.kind.name}-${b.sel.index}'),
                  left: false,
                  onDelta: (d) => resize(startSide: false, dMs: d),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Time marks along the top of the timeline.
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pxPerMs,
    required this.totalMs,
    required this.pad,
    required this.color,
  });

  final double pxPerMs;
  final int totalMs;
  final double pad;
  final Color color;

  /// Spacing of the labelled marks: the smallest step that is at least 70 px.
  static const _steps = [
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    15000,
    30000,
    60000,
    120000,
    300000,
    600000,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    var step = _steps.last;
    for (final s in _steps) {
      if (s * pxPerMs >= 70) {
        step = s;
        break;
      }
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final minor = step ~/ 5 > 0 ? step ~/ 5 : step;
    for (var ms = 0; ms <= totalMs + step; ms += minor) {
      final x = pad + ms * pxPerMs;
      final major = ms % step == 0;
      canvas.drawLine(
        Offset(x, size.height - (major ? 8 : 4)),
        Offset(x, size.height),
        paint,
      );
      if (major) {
        final text = step < 1000
            ? '${(ms / 1000).toStringAsFixed(1)}s'
            : _label(ms);
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(color: color, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 2));
      }
    }
  }

  String _label(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pxPerMs != pxPerMs || old.totalMs != totalMs || old.pad != pad;
}
