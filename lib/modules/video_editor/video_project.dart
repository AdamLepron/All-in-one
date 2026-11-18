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
    this.volume = 1,
    this.fade = false,
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

  /// Sound level of this clip, from 0 (silent) to 2 (twice as loud).
  double volume;

  /// Fades to black at the end of this clip and back in on the next one.
  bool fade;

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
    volume: volume,
    fade: fade,
  );

  Map<String, Object?> toJson() => {
    'media': media.toJson(),
    'start': startMs,
    'end': endMs,
    'speed': speed,
    'rotation': rotation,
    'volume': volume,
    'fade': fade,
  };

  static Clip fromJson(Map<String, dynamic> j) => Clip(
    Media.fromJson(j['media'] as Map<String, dynamic>),
    startMs: j['start'] as int,
    endMs: j['end'] as int,
    speed: (j['speed'] as num).toDouble(),
    rotation: j['rotation'] as int,
    volume: (j['volume'] as num?)?.toDouble() ?? 1,
    fade: j['fade'] as bool? ?? false,
  );
}

/// Where a title sits in the frame.
enum TitlePlace {
  top('Haut'),
  middle('Centre'),
  bottom('Bas');

  const TitlePlace(this.label);
  final String label;
}

/// Text shown over the montage between two moments of the finished video.
class TitleItem {
  TitleItem(
    this.text, {
    this.startMs = 0,
    this.endMs = 3000,
    this.place = TitlePlace.bottom,
    this.size = 0.06,
    this.color = 0xFFFFFFFF,
  });

  String text;

  /// Moments in the finished video.
  int startMs;
  int endMs;
  TitlePlace place;

  /// Text height as a fraction of the frame's height.
  double size;
  int color;

  Map<String, Object?> toJson() => {
    'text': text,
    'start': startMs,
    'end': endMs,
    'place': place.name,
    'size': size,
    'color': color,
  };

  static TitleItem fromJson(Map<String, dynamic> j) => TitleItem(
    j['text'] as String,
    startMs: j['start'] as int,
    endMs: j['end'] as int,
    place: TitlePlace.values.firstWhere(
      (p) => p.name == j['place'],
      orElse: () => TitlePlace.bottom,
    ),
    size: (j['size'] as num).toDouble(),
    color: j['color'] as int,
  );
}

/// Length of a fade to black, in milliseconds.
const fadeMs = 600;

/// A montage: clips played one after another, with optional audio changes.
class VideoProject {
  VideoProject(Media first, {String? id})
    : clips = [Clip(first)],
      id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
      created = DateTime.now(),
      name = first.name.replaceAll(RegExp(r'\.[^.]*$'), '');

  VideoProject._(this.id, this.name, this.created, this.clips);

  /// Identity of a saved project.
  final String id;
  String name;
  final DateTime created;
  final List<Clip> clips;
  bool muteOriginal = false;
  String? musicPath;
  String? musicName;

  /// Music level, from 0 to 2.
  double musicVolume = 1;
  final List<TitleItem> titles = [];

  /// Fade in from black at the very start.
  bool openingFade = false;

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

  /// Cuts the clip at [index] in two at [sourceMs] (a moment of the source
  /// video). False when one of the parts would be too short.
  bool split(int index, int sourceMs) {
    final c = clips[index];
    if (sourceMs - c.startMs < minClipMs || c.endMs - sourceMs < minClipMs) {
      return false;
    }
    final second = c.copy()..startMs = sourceMs;
    c.endMs = sourceMs;
    // A fade belongs to the end of the clip: it moves to the second part.
    second.fade = c.fade;
    c.fade = false;
    clips.insert(index + 1, second);
    return true;
  }

  /// Start of clip [index] in the finished video.
  int startOf(int index) {
    var t = 0;
    for (var i = 0; i < index; i++) {
      t += clips[i].outputMs;
    }
    return t;
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
      'musicVolume': musicVolume,
      'clips': [
        for (var i = 0; i < clips.length; i++)
          {
            'uri': clips[i].media.uri,
            'startMs': clips[i].startMs,
            'endMs': clips[i].endMs,
            'speed': clips[i].speed,
            'rotation': clips[i].rotation,
            'volume': clips[i].volume,
            'fadeInMs': _fadeIn(i),
            'fadeOutMs': _fadeOut(i),
          },
      ],
      'titles': [
        for (final t in titles)
          if (t.text.trim().isNotEmpty && t.startMs < totalMs)
            {
              'text': t.text,
              'startMs': t.startMs,
              'endMs': t.endMs.clamp(t.startMs + 1, totalMs),
              'place': t.place.index,
              'size': t.size,
              'color': t.color,
            },
      ],
    };
  }

  /// Fade-in of clip [i]: from black at the start, or after a faded clip.
  int _fadeIn(int i) {
    final wanted = i == 0 ? openingFade : clips[i - 1].fade;
    return wanted ? math.min(fadeMs, clips[i].outputMs ~/ 2) : 0;
  }

  int _fadeOut(int i) =>
      clips[i].fade ? math.min(fadeMs, clips[i].outputMs ~/ 2) : 0;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created': created.millisecondsSinceEpoch,
    'clips': [for (final c in clips) c.toJson()],
    'muteOriginal': muteOriginal,
    'music': musicPath,
    'musicName': musicName,
    'musicVolume': musicVolume,
    'titles': [for (final t in titles) t.toJson()],
    'openingFade': openingFade,
  };

  static VideoProject fromJson(Map<String, dynamic> j) {
    final clips = [
      for (final c in j['clips'] as List)
        Clip.fromJson(c as Map<String, dynamic>),
    ];
    if (clips.isEmpty) throw const FormatException('Projet vide');
    return VideoProject._(
        j['id'] as String,
        (j['name'] as String?) ?? 'Montage',
        DateTime.fromMillisecondsSinceEpoch(j['created'] as int),
        clips,
      )
      ..muteOriginal = j['muteOriginal'] as bool? ?? false
      ..musicPath = j['music'] as String?
      ..musicName = j['musicName'] as String?
      ..musicVolume = (j['musicVolume'] as num?)?.toDouble() ?? 1
      ..openingFade = j['openingFade'] as bool? ?? false
      ..titles.addAll([
        for (final t in (j['titles'] as List? ?? const []))
          TitleItem.fromJson(t as Map<String, dynamic>),
      ]);
  }
}

/// "0:03,4", "1:02,0": minutes, seconds and tenths.
String clock(int ms) {
  final tenths = (ms / 100).round();
  final m = tenths ~/ 600;
  final s = tenths % 600 ~/ 10;
  return '$m:${s.toString().padLeft(2, '0')},${tenths % 10}';
}
