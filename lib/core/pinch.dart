import 'package:flutter/widgets.dart';

/// Detects a two-finger pinch from raw pointers, so it works on top of
/// scrollable content without fighting its drag gestures.
class PinchDetector extends StatefulWidget {
  const PinchDetector({
    super.key,
    required this.child,
    this.onStart,
    this.onUpdate,
    this.onEnd,
  });

  final Widget child;
  final VoidCallback? onStart;

  /// Current distance between the fingers relative to the starting one.
  final ValueChanged<double>? onUpdate;

  /// Final scale when a finger lifts.
  final ValueChanged<double>? onEnd;

  @override
  State<PinchDetector> createState() => _PinchDetectorState();
}

class _PinchDetectorState extends State<PinchDetector> {
  final _pointers = <int, Offset>{};
  double? _startDistance;
  double _scale = 1;

  double get _distance {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  void _finish() {
    if (_startDistance == null) return;
    _startDistance = null;
    widget.onEnd?.call(_scale);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _pointers[e.pointer] = e.position;
        if (_pointers.length == 2) {
          _startDistance = _distance;
          _scale = 1;
          widget.onStart?.call();
        } else {
          _finish();
        }
      },
      onPointerMove: (e) {
        if (!_pointers.containsKey(e.pointer)) return;
        _pointers[e.pointer] = e.position;
        final start = _startDistance;
        if (start != null && start > 0 && _pointers.length == 2) {
          _scale = _distance / start;
          widget.onUpdate?.call(_scale);
        }
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        _finish();
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        _finish();
      },
      child: widget.child,
    );
  }
}
