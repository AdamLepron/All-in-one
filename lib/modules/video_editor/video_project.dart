import 'dart:math' as math;
import 'dart:ui';

import '../gallery/media_library.dart';

const speedChoices = <double>[0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4];

/// Shortest clip that can be kept.
const minClipMs = 500;

/// Longest side of the exported video; larger sources are scaled down.
const maxExportSide = 1920;

/// A part of a video, with its own speed and rotation.
class Clip {
  Clip(
    this.media, {
    int? startMs,
    int? endMs,
    this.speed = 1,
    this.rotation = 0,
    this.shownSize,
  }) : startMs = startMs ?? 0,
       endMs = endMs ?? media.duration.inMilliseconds;

  final Media media;
  int startMs;
  int endMs;
  double speed;

  /// Clockwise degrees: 0, 90, 180 or 270.
  int rotation;

  /// Size as displayed (rotation metadata applied), once known.
  Size? shownSize;

  int get sourceMs => media.duration.inMilliseconds;
  int get keptMs => endMs - startMs;

  /// Length in the finished video.
  int get outputMs => (keptMs / speed).round();

  /// Size after the user's rotation.
  Size get orientedSize {
    final base =
        shownSize ?? Size(media.width.toDouble(), media.height.toDouble());
    return rotation % 180 == 0 ? base : Size(base.height, base.width);
  }

  void setStart(int ms) =>
      startMs = ms.clamp(0, math.max(0, endMs - minClipMs));
  void setEnd(int ms) =>
      endMs = ms.clamp(math.min(sourceMs, startMs + minClipMs), sourceMs);

  void rotateClockwise() => rotation = (rotation + 90) % 360;

  Clip copy() => Clip(
    media,
    startMs: startMs,
    endMs: endMs,
    speed: speed,
    rotation: rotation,
    shownSize: shownSize,
  );
}

/// A montage: clips played one after another, with optional audio changes.
class VideoProject {
  VideoProject(Media first) : clips = [Clip(first)];

  final List<Clip> clips;
  bool muteOriginal = false;
  String? musicPath;
  String? musicName;

  int get totalMs => clips.fold(0, (sum, c) => sum + c.outputMs);

  /// Frame of the finished video: the first clip's shape, scaled down to
  /// at most [maxExportSide] and with even sides, as video encoders need.
  Size get outputSize {
    final s = clips.first.orientedSize;
    final w = s.width <= 0 || s.height <= 0 ? 1280.0 : s.width;
    final h = s.width <= 0 || s.height <= 0 ? 720.0 : s.height;
    final scale = math.min(1.0, maxExportSide / math.max(w, h));
    int even(double v) => math.max(2, (v * scale / 2).round() * 2);
    return Size(even(w).toDouble(), even(h).toDouble());
  }

  void move(int from, int to) {
    final clip = clips.removeAt(from);
    clips.insert(to > from ? to - 1 : to, clip);
  }

  /// Why the project cannot be exported, or null if it can.
  String? get problem {
    if (clips.isEmpty) return 'Ajoutez au moins une vidéo';
    for (final c in clips) {
      if (c.keptMs < minClipMs) return 'Un extrait est trop court';
    }
    // Four hours of 1080p is far beyond what a phone finishes.
    if (totalMs > 4 * 3600 * 1000) return 'Le montage dépasse 4 heures';
    return null;
  }

  /// Arguments for the native exporter.
  Map<String, Object?> exportArgs(String output) {
    final size = outputSize;
    return {
      'output': output,
      'width': size.width.round(),
      'height': size.height.round(),
      'muteOriginal': muteOriginal,
      'music': musicPath,
      'clips': [
        for (final c in clips)
          {
            'uri': c.media.uri,
            'startMs': c.startMs,
            'endMs': c.endMs,
            'speed': c.speed,
            'rotation': c.rotation,
          },
      ],
    };
  }
}

/// "0:03,4", "1:02,0": minutes, seconds and tenths.
String clock(int ms) {
  final tenths = (ms / 100).round();
  final m = tenths ~/ 600;
  final s = tenths % 600 ~/ 10;
  return '$m:${s.toString().padLeft(2, '0')},${tenths % 10}';
}
