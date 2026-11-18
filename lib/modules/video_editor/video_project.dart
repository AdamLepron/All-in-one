import 'dart:math' as math;
import 'dart:ui';

import '../gallery/media_library.dart';

const speedChoices = <double>[0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4];

/// Slowest and fastest speed a clip can be given.
const minSpeed = 0.1;
const maxSpeed = 8.0;

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

/// How a clip hands over to the next one.
enum TransitionKind {
  none('Aucune'),
  fade('Fondu noir'),
  flash('Flash blanc'),
  slideLeft('Glissé ←'),
  slideRight('Glissé →'),
  zoom('Zoom');

  const TransitionKind(this.label);
  final String label;
}

/// Longest image clip, in milliseconds.
const maxImageMs = 60000;

/// Length of an image clip when it is added.
const defaultImageMs = 4000;

/// A part of a video (or a still image shown for a while), with its own
/// speed and rotation.
class VideoClip {
  VideoClip(
    this.media, {
    int? startMs,
    int? endMs,
    this.speed = 1,
    this.rotation = 0,
    this.shownSize,
    this.volume = 1,
    bool fade = false,
    TransitionKind? transition,
    this.transitionMs = fadeMs,
    this.filter = VideoFilter.none,
    this.brightness = 1,
    this.contrastAdjust = 0,
    this.saturationAdjust = 1,
    this.effect = ClipEffect.none,
    this.blur = 0,
    this.flip = false,
  }) : startMs = startMs ?? 0,
       endMs =
           endMs ??
           (media.video ? media.duration.inMilliseconds : defaultImageMs),
       transition =
           transition ?? (fade ? TransitionKind.fade : TransitionKind.none);

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

  /// How this clip hands over to the next one (or closes the video).
  TransitionKind transition;

  /// Length of that transition, in milliseconds.
  int transitionMs;

  /// Fades to black at the end of this clip and back in on the next one.
  bool get fade => transition == TransitionKind.fade;
  set fade(bool v) {
    if (v) {
      transition = TransitionKind.fade;
    } else if (transition == TransitionKind.fade) {
      transition = TransitionKind.none;
    }
  }

  /// A still picture rather than a video.
  bool get isImage => !media.video;

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

  int get sourceMs => isImage ? maxImageMs : media.duration.inMilliseconds;
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

  VideoClip copy() => VideoClip(
    media,
    startMs: startMs,
    endMs: endMs,
    speed: speed,
    rotation: rotation,
    shownSize: shownSize,
    volume: volume,
    transition: transition,
    transitionMs: transitionMs,
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
    if (shownSize != null) ...{'w': shownSize!.width, 'h': shownSize!.height},
    'transition': transition.name,
    'transitionMs': transitionMs,
    'filter': filter.name,
    'brightness': brightness,
    'contrast': contrastAdjust,
    'saturation': saturationAdjust,
    'effect': effect.name,
    'blur': blur,
    'flip': flip,
  };

  static VideoClip fromJson(Map<String, dynamic> j) => VideoClip(
    Media.fromJson(j['media'] as Map<String, dynamic>),
    startMs: j['start'] as int,
    endMs: j['end'] as int,
    speed: (j['speed'] as num).toDouble(),
    rotation: j['rotation'] as int,
    volume: (j['volume'] as num?)?.toDouble() ?? 1,
    fade: j['fade'] as bool? ?? false,
    shownSize: j['w'] is num && j['h'] is num
        ? Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble())
        : null,
    transition: TransitionKind.values
        .where((t) => t.name == j['transition'])
        .firstOrNull,
    transitionMs: ((j['transitionMs'] as num?)?.toInt() ?? fadeMs).clamp(
      200,
      2000,
    ),
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
    this.x,
    this.y,
    this.animation = TitleAnimation.none,
    this.box = TitleBox.shade,
  });

  String text;

  /// −1 left, 0 centre, 1 right.
  int align;

  /// Free position of the centre, as fractions (0–1) of the frame; when
  /// set, it replaces [place] and [align].
  double? x;
  double? y;
  TitleAnimation animation;
  TitleBox box;

  /// Moments in the finished video.
  int startMs;
  int endMs;
  TitlePlace place;

  /// Text height as a fraction of the frame's height.
  double size;
  int color;

  /// A copy with the same style, to be placed elsewhere in time.
  TitleItem copyWith() => TitleItem(
    text,
    startMs: startMs,
    endMs: endMs,
    place: place,
    size: size,
    color: color,
    align: align,
    x: x,
    y: y,
    animation: animation,
    box: box,
  );

  Map<String, Object?> toJson() => {
    'text': text,
    'start': startMs,
    'end': endMs,
    'place': place.name,
    'size': size,
    'color': color,
    'align': align,
    'x': x,
    'y': y,
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
    x: (j['x'] as num?)?.toDouble().clamp(0.0, 1.0),
    y: (j['y'] as num?)?.toDouble().clamp(0.0, 1.0),
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

/// A picture or a video laid over the montage on its own track.
class OverlayClip {
  OverlayClip(
    this.media, {
    this.startMs = 0,
    this.trimStartMs = 0,
    int? durationMs,
    this.cx = 0.72,
    this.cy = 0.28,
    this.width = 0.34,
    this.opacity = 1,
    this.volume = 0,
    this.track = 0,
  }) : durationMs =
           durationMs ??
           (media.video
               ? math.min(media.duration.inMilliseconds, 5000)
               : defaultImageMs);

  final Media media;

  /// Moment of the finished video where it appears.
  int startMs;

  /// For a video: where in the source it starts.
  int trimStartMs;

  /// How long it stays.
  int durationMs;

  /// Centre of the picture, as fractions (0–1) of the frame.
  double cx;
  double cy;

  /// Width as a fraction of the frame's width.
  double width;
  double opacity;

  /// Sound of an overlaid video (0 = silent, the default).
  double volume;

  /// Lane (0 is the lowest); a higher lane is drawn on top.
  int track;

  bool get isImage => !media.video;
  int get endMs => startMs + durationMs;

  /// Longest it can last: a video's remaining source, or an image's limit.
  int get maxDurationMs => isImage
      ? maxImageMs
      : math.max(minClipMs, media.duration.inMilliseconds - trimStartMs);

  OverlayClip copy() => OverlayClip(
    media,
    startMs: startMs,
    trimStartMs: trimStartMs,
    durationMs: durationMs,
    cx: cx,
    cy: cy,
    width: width,
    opacity: opacity,
    volume: volume,
    track: track,
  );

  Map<String, Object?> toJson() => {
    'media': media.toJson(),
    'start': startMs,
    'trim': trimStartMs,
    'duration': durationMs,
    'cx': cx,
    'cy': cy,
    'width': width,
    'opacity': opacity,
    'volume': volume,
    'track': track,
  };

  static OverlayClip fromJson(Map<String, dynamic> j) => OverlayClip(
    Media.fromJson(j['media'] as Map<String, dynamic>),
    startMs: ((j['start'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
    trimStartMs: ((j['trim'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
    durationMs: ((j['duration'] as num?)?.toInt() ?? defaultImageMs).clamp(
      minClipMs,
      1 << 31,
    ),
    cx: ((j['cx'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
    cy: ((j['cy'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
    width: ((j['width'] as num?)?.toDouble() ?? 0.34).clamp(0.05, 1.0),
    opacity: ((j['opacity'] as num?)?.toDouble() ?? 1).clamp(0.1, 1.0),
    volume: ((j['volume'] as num?)?.toDouble() ?? 0).clamp(0.0, 2.0),
    track: ((j['track'] as num?)?.toInt() ?? 0).clamp(0, overlayLanes - 1),
  );
}

/// How many lanes of overlays the timeline offers.
const overlayLanes = 3;

/// A sound (music, effect, voice) placed on the montage's timeline.
class AudioClip {
  AudioClip(
    this.path,
    this.name, {
    this.startMs = 0,
    this.trimStartMs = 0,
    required this.durationMs,
    this.sourceMs = 0,
    this.volume = 1,
  });

  final String path;
  final String name;

  /// Moment of the finished video where it starts.
  int startMs;

  /// Where in the file it starts playing.
  int trimStartMs;
  int durationMs;

  /// Length of the whole file when known (0 = unknown).
  int sourceMs;

  /// 0 (silent) … 2.
  double volume;

  int get endMs => startMs + durationMs;

  /// Longest it can last from its start point.
  int get maxDurationMs =>
      sourceMs > 0 ? math.max(minClipMs, sourceMs - trimStartMs) : 1 << 31;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'start': startMs,
    'trim': trimStartMs,
    'duration': durationMs,
    'source': sourceMs,
    'volume': volume,
  };

  static AudioClip fromJson(Map<String, dynamic> j) => AudioClip(
    j['path'] as String,
    (j['name'] as String?) ?? 'Son',
    startMs: ((j['start'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
    trimStartMs: ((j['trim'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
    durationMs: ((j['duration'] as num?)?.toInt() ?? 5000).clamp(
      minClipMs,
      1 << 31,
    ),
    sourceMs: (j['source'] as num?)?.toInt() ?? 0,
    volume: ((j['volume'] as num?)?.toDouble() ?? 1).clamp(0.0, 2.0),
  );
}

/// How a clip's picture is moved and dimmed at one moment: the same
/// formulas as the exporter, so the preview shows what will be made.
class ClipPose {
  const ClipPose({this.scale = 1, this.dx = 0, this.dy = 0, this.gain = 1});

  /// Enlargement around the centre.
  final double scale;

  /// Shift, where 2 is the whole width (or height) of the frame.
  final double dx;
  final double dy;

  /// Brightness multiplier: 0 black, 1 as is, above 1 burns to white.
  final double gain;

  bool get isNeutral => scale == 1 && dx == 0 && dy == 0 && gain == 1;
}

double _ease(double x) {
  final k = x.clamp(0.0, 1.0);
  return k * k * (3 - 2 * k);
}

/// Image clips and any clip showing in the preview: a clip's pose
/// at [outMs] after its start in the finished video.
ClipPose clipPoseAt({
  required ClipEffect effect,
  required int outMs,
  required int durationMs,
  TransitionKind arriving = TransitionKind.none,
  int arrivingMs = 0,
  TransitionKind leaving = TransitionKind.none,
  int leavingMs = 0,
  int fadeInMs = 0,
  int fadeOutMs = 0,
}) {
  var scale = 1.0, dx = 0.0, dy = 0.0, gain = 1.0;
  final sec = outMs / 1000;
  final p = durationMs <= 0 ? 0.0 : (outMs / durationMs).clamp(0.0, 1.0);
  switch (effect) {
    case ClipEffect.none:
      break;
    case ClipEffect.zoomIn:
      scale = 1 + 0.25 * p;
    case ClipEffect.zoomOut:
      scale = 1.25 - 0.25 * p;
    case ClipEffect.pulse:
      scale = 1 + 0.06 * (0.5 + 0.5 * math.sin(sec * 2 * math.pi / 0.8));
    case ClipEffect.shake:
      scale = 1.06;
      dx = 0.02 * math.sin(sec * 38);
      dy = 0.02 * math.sin(sec * 51 + 1);
  }
  void apply(TransitionKind kind, double k, bool arrives) {
    if (k <= 0) return;
    switch (kind) {
      case TransitionKind.slideLeft:
        dx += arrives ? 2 * k : -2 * k;
      case TransitionKind.slideRight:
        dx += arrives ? -2 * k : 2 * k;
      case TransitionKind.zoom:
        scale *= 1 + 0.6 * k;
        gain *= 1 - k;
      case TransitionKind.flash:
        gain *= 1 + 11 * k * k;
      case TransitionKind.none:
      case TransitionKind.fade:
        break;
    }
  }

  if (arriving != TransitionKind.none && arrivingMs > 0 && outMs < arrivingMs) {
    apply(arriving, 1 - _ease(outMs / arrivingMs), true);
  }
  final outStart = durationMs - leavingMs;
  if (leaving != TransitionKind.none && leavingMs > 0 && outMs > outStart) {
    apply(leaving, _ease((outMs - outStart) / leavingMs), false);
  }
  // Fades to black (linear, as in the exporter).
  if (fadeInMs > 0 && outMs < fadeInMs) gain *= outMs / fadeInMs;
  if (fadeOutMs > 0 && outMs > durationMs - fadeOutMs) {
    gain *= (1 - (outMs - (durationMs - fadeOutMs)) / fadeOutMs).clamp(
      0.0,
      1.0,
    );
  }
  return ClipPose(scale: scale, dx: dx, dy: dy, gain: gain.clamp(0.0, 12.0));
}

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
    : clips = [VideoClip(first)],
      id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
      created = DateTime.now(),
      name = first.name.replaceAll(RegExp(r'\.[^.]*$'), '');

  VideoProject._(this.id, this.name, this.created, this.clips);

  /// Identity of a saved project.
  final String id;
  String name;
  final DateTime created;
  final List<VideoClip> clips;
  bool muteOriginal = false;
  String? musicPath;
  String? musicName;

  /// Music level, from 0 to 2.
  double musicVolume = 1;
  final List<TitleItem> titles = [];

  /// Pictures and videos over the main track.
  final List<OverlayClip> overlays = [];

  /// Sounds placed on the timeline, on top of the music.
  final List<AudioClip> sounds = [];

  /// Fade in from black at the very start.
  bool openingFade = false;

  /// Frame shape, and whether clips fill it (cropped) or fit in it (bars).
  Aspect aspect = Aspect.original;
  bool fillFrame = false;

  int get totalMs => clips.fold(0, (sum, c) => sum + c.outputMs);

  /// The clip showing at [timeMs] of the finished video, and how far into
  /// it (in finished-video milliseconds). The very end belongs to the last.
  (int index, int offsetMs) locate(int timeMs) {
    var start = 0;
    for (var i = 0; i < clips.length; i++) {
      final len = clips[i].outputMs;
      if (timeMs < start + len || i == clips.length - 1) {
        return (i, (timeMs - start).clamp(0, len));
      }
      start += len;
    }
    return (0, 0);
  }

  /// Cuts whichever clip is showing at [timeMs] in two. Returns the index of
  /// the second part, or null when the cut would leave a part under 0.5 s.
  int? splitAtTime(int timeMs) {
    final (i, offset) = locate(timeMs);
    final c = clips[i];
    final source = c.startMs + (offset * c.speed).round();
    return split(i, source) ? i + 1 : null;
  }

  /// Gives this montage the content of [other] (used by undo and redo).
  void replaceWith(VideoProject other) {
    name = other.name;
    clips
      ..clear()
      ..addAll(other.clips);
    titles
      ..clear()
      ..addAll(other.titles);
    overlays
      ..clear()
      ..addAll(other.overlays);
    sounds
      ..clear()
      ..addAll(other.sounds);
    muteOriginal = other.muteOriginal;
    musicPath = other.musicPath;
    musicName = other.musicName;
    musicVolume = other.musicVolume;
    openingFade = other.openingFade;
    aspect = other.aspect;
    fillFrame = other.fillFrame;
  }

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
    second.transition = c.transition;
    second.transitionMs = c.transitionMs;
    c.transition = TransitionKind.none;
    clips.insert(index + 1, second);
    return true;
  }

  /// Removes the passage [fromMs]–[toMs] (moments of the source video) from
  /// the clip at [index]: what is left on each side stays as two clips. False
  /// when nothing sensible would remain or the passage is empty.
  bool cutOut(int index, int fromMs, int toMs) {
    final c = clips[index];
    if (c.isImage) return false;
    final from = math.max(fromMs, c.startMs);
    final to = math.min(toMs, c.endMs);
    if (to - from < 100) return false;
    final leftOk = from - c.startMs >= minClipMs;
    final rightOk = c.endMs - to >= minClipMs;
    if (!leftOk && !rightOk) return false;
    if (leftOk && rightOk) {
      final second = c.copy()..startMs = to;
      // A transition belongs to the end of the clip: the second part keeps it.
      second.transition = c.transition;
      second.transitionMs = c.transitionMs;
      c.endMs = from;
      c.transition = TransitionKind.none;
      clips.insert(index + 1, second);
    } else if (leftOk) {
      c.endMs = from; // the end of the clip is what was removed
    } else {
      c.startMs = to;
    }
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
    for (final o in overlays) {
      if (o.durationMs < minClipMs) return 'Une incrustation est trop courte';
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
            if (clips[i].isImage) 'image': true,
            ..._slide(i),
            'flip': clips[i].flip,
            'effect': clips[i].effect.index,
            'blur': clips[i].blur,
            if (!clips[i].look.isNeutral) ...{
              'colorMatrix': clips[i].look.columnMajor4,
              'contrast': clips[i].look.contrast,
            },
          },
      ],
      if (overlays.isNotEmpty)
        'overlays': [
          for (final o in overlays)
            if (o.startMs < totalMs)
              {
                'image': o.isImage,
                'uri': o.media.uri,
                'startMs': o.startMs,
                'trimStartMs': o.trimStartMs,
                'durationMs': math.min(o.durationMs, totalMs - o.startMs),
                'cx': o.cx,
                'cy': o.cy,
                'width': o.width,
                'opacity': o.opacity,
                'volume': o.volume,
                'track': o.track,
                'aspect': o.media.width > 0 && o.media.height > 0
                    ? o.media.width / o.media.height
                    : 16 / 9,
              },
        ],
      if (sounds.isNotEmpty)
        'sounds': [
          for (final a in sounds)
            if (a.startMs < totalMs)
              {
                'path': a.path,
                'startMs': a.startMs,
                'trimStartMs': a.trimStartMs,
                'durationMs': math.min(a.durationMs, totalMs - a.startMs),
                'volume': a.volume,
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
              if (t.x != null && t.y != null) ...{'x': t.x, 'y': t.y},
              'animation': t.animation.index,
              'box': t.box.index,
            },
      ],
    };
  }

  /// Where clip [i] stands [outMs] after its start, transitions included.
  ClipPose poseAt(int i, int outMs) {
    final c = clips[i];
    final prev = i > 0 ? clips[i - 1] : null;
    final last = i == clips.length - 1;
    bool special(TransitionKind k) =>
        k != TransitionKind.none && k != TransitionKind.fade;
    return clipPoseAt(
      effect: c.effect,
      outMs: outMs,
      durationMs: c.outputMs,
      arriving: prev != null && special(prev.transition)
          ? prev.transition
          : TransitionKind.none,
      arrivingMs: prev == null
          ? 0
          : math.min(prev.transitionMs, c.outputMs ~/ 2),
      leaving: !last && special(c.transition)
          ? c.transition
          : TransitionKind.none,
      leavingMs: math.min(c.transitionMs, c.outputMs ~/ 2),
      fadeInMs: _fadeIn(i),
      fadeOutMs: _fadeOut(i),
    );
  }

  /// Fade-in of clip [i]: from black at the start, or after a faded clip.
  int _fadeIn(int i) {
    final wanted = i == 0 ? openingFade : clips[i - 1].fade;
    if (!wanted) return 0;
    final span = i == 0 ? fadeMs : clips[i - 1].transitionMs;
    return math.min(span, clips[i].outputMs ~/ 2);
  }

  int _fadeOut(int i) => clips[i].fade
      ? math.min(clips[i].transitionMs, clips[i].outputMs ~/ 2)
      : 0;

  /// Transitions other than the fade to black: how clip [i] leaves and
  /// how it arrives after the previous one. The last clip only closes.
  Map<String, Object?> _slide(int i) {
    bool special(TransitionKind k) =>
        k != TransitionKind.none && k != TransitionKind.fade;
    final out = clips[i].transition;
    final inn = i > 0 ? clips[i - 1].transition : TransitionKind.none;
    final last = i == clips.length - 1;
    return {
      if (!last && special(out)) ...{
        'trOut': out.index,
        'trOutMs': math.min(clips[i].transitionMs, clips[i].outputMs ~/ 2),
      },
      if (special(inn)) ...{
        'trIn': inn.index,
        'trInMs': math.min(clips[i - 1].transitionMs, clips[i].outputMs ~/ 2),
      },
    };
  }

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
    'overlays': [for (final o in overlays) o.toJson()],
    'sounds': [for (final a in sounds) a.toJson()],
    'aspect': aspect.name,
    'fill': fillFrame,
  };

  static VideoProject fromJson(Map<String, dynamic> j) {
    final clips = [
      for (final c in j['clips'] as List)
        VideoClip.fromJson(c as Map<String, dynamic>),
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
      ..overlays.addAll([
        for (final o in (j['overlays'] as List? ?? const []))
          OverlayClip.fromJson(o as Map<String, dynamic>),
      ])
      ..sounds.addAll([
        for (final a in (j['sounds'] as List? ?? const []))
          AudioClip.fromJson(a as Map<String, dynamic>),
      ])
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
