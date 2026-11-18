import 'dart:math' as math;
import 'dart:ui';

import '../gallery/media_library.dart';

const speedChoices = <double>[0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4];

/// Shortest clip that can be kept.
const minClipMs = 500;

/// Longest side of the exported video; larger sources are scaled down.
const maxExportSide = 1920;

/// A ready-made look for a clip (a colour matrix, like a phone-camera filter).
enum VideoFilter {
  none('Original', 0xFF607D8B),
  mono('Noir et blanc', 0xFF9E9E9E),
  noir('Noir intense', 0xFF212121),
  sepia('Sépia', 0xFF8D6E63),
  vintage('Vintage', 0xFFC49A6C),
  warm('Chaud', 0xFFFF8F3F),
  cool('Froid', 0xFF42A5F5),
  vivid('Éclatant', 0xFFE91E63),
  faded('Délavé', 0xFFB0BEC5),
  cinema('Cinéma', 0xFF00897B);

  const VideoFilter(this.label, this.swatch);
  final String label;

  /// Colour shown on the filter's button.
  final int swatch;
}

/// A motion applied to a whole clip.
enum ClipEffect {
  none('Aucun'),
  zoomIn('Zoom avant'),
  zoomOut('Zoom arrière'),
  pulse('Pulsation'),
  shake('Secousse');

  const ClipEffect(this.label);
  final String label;
}

typedef _M3 = List<double>; // 3×3, row-major

const _identity = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];

_M3 _mul(_M3 a, _M3 b) => [
  for (var r = 0; r < 3; r++)
    for (var c = 0; c < 3; c++)
      a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
];

_M3 _lerp(_M3 a, _M3 b, double t) => [
  for (var i = 0; i < 9; i++) a[i] + (b[i] - a[i]) * t,
];

_M3 _diag(double r, double g, double b) => [r, 0, 0, 0, g, 0, 0, 0, b];

/// Saturation 0 (grey) … 1 (unchanged) … 2 (strong).
_M3 _saturation(double s) {
  const wr = 0.2126, wg = 0.7152, wb = 0.0722;
  return [
    wr * (1 - s) + s, wg * (1 - s), wb * (1 - s), //
    wr * (1 - s), wg * (1 - s) + s, wb * (1 - s),
    wr * (1 - s), wg * (1 - s), wb * (1 - s) + s,
  ];
}

const _sepiaMatrix = <double>[
  0.393, 0.769, 0.189, //
  0.349, 0.686, 0.168,
  0.272, 0.534, 0.131,
];

/// Colour matrix and extra contrast of a preset.
(_M3, double) _presetOf(VideoFilter f) => switch (f) {
  VideoFilter.none => (_identity, 0),
  VideoFilter.mono => (_saturation(0), 0),
  VideoFilter.noir => (_saturation(0), 0.35),
  VideoFilter.sepia => (_sepiaMatrix, 0),
  VideoFilter.vintage => (
    _mul(_lerp(_identity, _sepiaMatrix, 0.55), _saturation(0.85)),
    -0.1,
  ),
  VideoFilter.warm => (_diag(1.12, 1.0, 0.86), 0),
  VideoFilter.cool => (_diag(0.88, 1.0, 1.16), 0),
  VideoFilter.vivid => (_saturation(1.55), 0.12),
  VideoFilter.faded => (_saturation(0.65), -0.18),
  VideoFilter.cinema => (_mul(_diag(1.08, 0.99, 0.93), _saturation(1.1)), 0.15),
};

/// What the rendering of a clip looks like once colour settings apply.
class ClipLook {
  const ClipLook(this.matrix, this.contrast);

  /// 3×3 colour matrix, row-major.
  final List<double> matrix;

  /// −1 … 1, 0 = unchanged.
  final double contrast;

  bool get isNeutral =>
      contrast.abs() < 0.005 &&
      [for (var i = 0; i < 9; i++) (matrix[i] - _identity[i]).abs()]
          .every((d) => d < 0.005);

  /// For the native side: a 4×4 matrix in column-major order, alpha kept.
  List<double> get columnMajor4 => [
    matrix[0], matrix[3], matrix[6], 0, //
    matrix[1], matrix[4], matrix[7], 0,
    matrix[2], matrix[5], matrix[8], 0,
    0, 0, 0, 1,
  ];

  /// For the preview: Flutter's 5×4 colour filter, contrast included.
  List<double> get preview5x4 {
    final k = 1 + contrast;
    final o = 255 * 0.5 * (1 - k);
    return [
      matrix[0] * k, matrix[1] * k, matrix[2] * k, 0, o, //
      matrix[3] * k, matrix[4] * k, matrix[5] * k, 0, o,
      matrix[6] * k, matrix[7] * k, matrix[8] * k, 0, o,
      0, 0, 0, 1, 0,
    ];
  }
}

/// Part of a clip's frame that stays visible, as shown or exported.
const maxZoom = 1.25;

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
    this.filter = VideoFilter.none,
    this.brightness = 1,
    this.contrastAdjust = 0,
    this.saturationAdjust = 1,
    this.effect = ClipEffect.none,
    this.blur = 0,
    this.flip = false,
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

  /// Preset look, then the three adjustments on top of it.
  VideoFilter filter;

  /// Light level: 0.5 (darker) … 1 (unchanged) … 1.5 (brighter).
  double brightness;

  /// −0.5 … 0.5, 0 = unchanged.
  double contrastAdjust;

  /// 0 (grey) … 1 (unchanged) … 2.
  double saturationAdjust;

  /// A motion over the whole clip.
  ClipEffect effect;

  /// Blur strength, 0 (none) … 1 (strong).
  double blur;

  /// Mirrored left to right.
  bool flip;

  /// The colour treatment: preset, brightness, saturation and contrast.
  ClipLook get look {
    final (preset, presetContrast) = _presetOf(filter);
    final m = _mul(
      _mul(_saturation(saturationAdjust), preset),
      _diag(brightness, brightness, brightness),
    );
    return ClipLook(m, (presetContrast + contrastAdjust).clamp(-1.0, 1.0));
  }

  /// True when any look, effect, blur or mirror is set.
  bool get styled =>
      !look.isNeutral || effect != ClipEffect.none || blur > 0 || flip;

  /// Back to the untouched picture.
  void resetLook() {
    filter = VideoFilter.none;
    brightness = 1;
    contrastAdjust = 0;
    saturationAdjust = 1;
  }

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
    filter: filter,
    brightness: brightness,
    contrastAdjust: contrastAdjust,
    saturationAdjust: saturationAdjust,
    effect: effect,
    blur: blur,
    flip: flip,
  );

  Map<String, Object?> toJson() => {
    'media': media.toJson(),
    'start': startMs,
    'end': endMs,
    'speed': speed,
    'rotation': rotation,
    'volume': volume,
    'fade': fade,
    'filter': filter.name,
    'brightness': brightness,
    'contrast': contrastAdjust,
    'saturation': saturationAdjust,
    'effect': effect.name,
    'blur': blur,
    'flip': flip,
  };

  static Clip fromJson(Map<String, dynamic> j) => Clip(
    Media.fromJson(j['media'] as Map<String, dynamic>),
    startMs: j['start'] as int,
    endMs: j['end'] as int,
    speed: (j['speed'] as num).toDouble(),
    rotation: j['rotation'] as int,
    volume: (j['volume'] as num?)?.toDouble() ?? 1,
    fade: j['fade'] as bool? ?? false,
    filter: VideoFilter.values.firstWhere(
      (f) => f.name == j['filter'],
      orElse: () => VideoFilter.none,
    ),
    brightness: ((j['brightness'] as num?)?.toDouble() ?? 1).clamp(0.5, 1.5),
    contrastAdjust: ((j['contrast'] as num?)?.toDouble() ?? 0).clamp(-0.5, 0.5),
    saturationAdjust: ((j['saturation'] as num?)?.toDouble() ?? 1).clamp(
      0.0,
      2.0,
    ),
    effect: ClipEffect.values.firstWhere(
      (e) => e.name == j['effect'],
      orElse: () => ClipEffect.none,
    ),
    blur: ((j['blur'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    flip: j['flip'] as bool? ?? false,
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

/// How a title or sticker comes and goes.
enum TitleAnimation {
  none('Aucune'),
  fade('Fondu'),
  slide('Glissé'),
  pop('Rebond');

  const TitleAnimation(this.label);
  final String label;
}

/// Backdrop behind a title's text.
enum TitleBox {
  none('Sans fond'),
  shade('Ombré'),
  solid('Plein');

  const TitleBox(this.label);
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
    this.align = 0,
    this.animation = TitleAnimation.none,
    this.box = TitleBox.shade,
  });

  String text;

  /// −1 left, 0 centre, 1 right.
  int align;
  TitleAnimation animation;
  TitleBox box;

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
    'align': align,
    'animation': animation.name,
    'box': box.name,
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
    align: ((j['align'] as num?)?.toInt() ?? 0).clamp(-1, 1),
    animation: TitleAnimation.values.firstWhere(
      (a) => a.name == j['animation'],
      orElse: () => TitleAnimation.none,
    ),
    box: TitleBox.values.firstWhere(
      (b) => b.name == j['box'],
      orElse: () => TitleBox.shade,
    ),
  );
}

/// Length of a fade to black, in milliseconds.
const fadeMs = 600;

/// Shape of the finished video.
enum Aspect {
  original('Original', 0),
  wide('16:9', 16 / 9),
  tall('9:16', 9 / 16),
  square('1:1', 1),
  portrait('4:5', 4 / 5),
  classic('4:3', 4 / 3);

  const Aspect(this.label, this.ratio);
  final String label;

  /// Width over height; 0 = that of the first clip.
  final double ratio;
}

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

  /// Frame shape, and whether clips fill it (cropped) or fit in it (bars).
  Aspect aspect = Aspect.original;
  bool fillFrame = false;

  int get totalMs => clips.fold(0, (sum, c) => sum + c.outputMs);

  /// Frame of the finished video: the first clip's shape, scaled down to
  /// at most [maxExportSide] and with even sides, as video encoders need.
  Size get outputSize {
    final s = clips.first.orientedSize;
    final w = s.width <= 0 || s.height <= 0 ? 1280.0 : s.width;
    final h = s.width <= 0 || s.height <= 0 ? 720.0 : s.height;
    int even(double v) => math.max(2, (v / 2).round() * 2);
    if (aspect == Aspect.original) {
      final scale = math.min(1.0, maxExportSide / math.max(w, h));
      return Size(even(w * scale).toDouble(), even(h * scale).toDouble());
    }
    // A chosen shape: its long side is that of the source, up to the limit.
    final longSide = math.min(maxExportSide.toDouble(), math.max(w, h));
    final r = aspect.ratio;
    return r >= 1
        ? Size(even(longSide).toDouble(), even(longSide / r).toDouble())
        : Size(even(longSide * r).toDouble(), even(longSide).toDouble());
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
      'fill': fillFrame,
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
            'flip': clips[i].flip,
            'effect': clips[i].effect.index,
            'blur': clips[i].blur,
            if (!clips[i].look.isNeutral) ...{
              'colorMatrix': clips[i].look.columnMajor4,
              'contrast': clips[i].look.contrast,
            },
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
              'align': t.align,
              'animation': t.animation.index,
              'box': t.box.index,
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
    'aspect': aspect.name,
    'fill': fillFrame,
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
      ..aspect = Aspect.values.firstWhere(
        (a) => a.name == j['aspect'],
        orElse: () => Aspect.original,
      )
      ..fillFrame = j['fill'] as bool? ?? false
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
