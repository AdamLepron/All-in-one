import 'dart:math' as math;
import 'dart:ui';

/// A colour matrix in Flutter's layout: 4 rows (R, G, B, A) of 5 values,
/// the fifth being an offset on the 0–255 scale.
typedef ColorMatrix = List<double>;

const identityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// Matrix that applies [first] and then [second].
ColorMatrix compose(ColorMatrix first, ColorMatrix second) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += second[row * 5 + k] * first[k * 5 + col];
      }
      if (col == 4) v += second[row * 5 + 4];
      out[row * 5 + col] = v;
    }
  }
  return out;
}

/// Blend between [identityMatrix] and [m]: 0 gives no effect, 1 the full one.
ColorMatrix blendWithIdentity(ColorMatrix m, double amount) => [
  for (var i = 0; i < 20; i++)
    identityMatrix[i] + (m[i] - identityMatrix[i]) * amount,
];

/// [amount] from -1 (darker) to 1 (brighter).
ColorMatrix brightnessMatrix(double amount) => [
  1, 0, 0, 0, amount * 100, //
  0, 1, 0, 0, amount * 100,
  0, 0, 1, 0, amount * 100,
  0, 0, 0, 1, 0,
];

/// [amount] from -1 (flat) to 1 (strong), pivoting around mid-grey.
ColorMatrix contrastMatrix(double amount) {
  final s = 1 + amount;
  final o = 128 * (1 - s);
  return [
    s, 0, 0, 0, o, //
    0, s, 0, 0, o,
    0, 0, s, 0, o,
    0, 0, 0, 1, 0,
  ];
}

/// [amount] from -1 (grey) to 1 (twice as colourful).
ColorMatrix saturationMatrix(double amount) {
  final s = 1 + amount;
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return [
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0, //
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// [amount] from -1 (cooler, bluer) to 1 (warmer, more orange).
ColorMatrix warmthMatrix(double amount) => [
  1, 0, 0, 0, amount * 28, //
  0, 1, 0, 0, amount * 6,
  0, 0, 1, 0, -amount * 28,
  0, 0, 0, 1, 0,
];

/// [amount] from 0 to 1: lifts the blacks and softens the whites.
ColorMatrix fadeMatrix(double amount) {
  final s = 1 - 0.3 * amount;
  final o = 255 * 0.15 * amount;
  return [
    s, 0, 0, 0, o, //
    0, s, 0, 0, o,
    0, 0, s, 0, o,
    0, 0, 0, 1, 0,
  ];
}

/// [amount] from -1 to 1: darkens or lightens by up to about 1.5 stops.
ColorMatrix exposureMatrix(double amount) {
  final g = math.pow(2, amount * 1.5).toDouble();
  return [
    g, 0, 0, 0, 0, //
    0, g, 0, 0, 0,
    0, 0, g, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// [amount] from -1 (greener) to 1 (more magenta).
ColorMatrix tintMatrix(double amount) => [
  1 + amount * 0.06, 0, 0, 0, 0, //
  0, 1 - amount * 0.12, 0, 0, 0,
  0, 0, 1 + amount * 0.06, 0, 0,
  0, 0, 0, 1, 0,
];

/// The sliders of the Adjust tab.
enum Adjust {
  exposure('Exposition', -100, 100),
  brightness('Luminosité', -100, 100),
  contrast('Contraste', -100, 100),
  saturation('Saturation', -100, 100),
  warmth('Chaleur', -100, 100),
  tint('Teinte', -100, 100),
  fade('Fondu', 0, 100),
  vignette('Vignette', 0, 100);

  const Adjust(this.label, this.min, this.max);
  final String label;
  final double min;
  final double max;
}

class PhotoFilter {
  const PhotoFilter(this.id, this.name, this.matrix);
  final String id;
  final String name;
  final ColorMatrix matrix;
}

final photoFilters = <PhotoFilter>[
  const PhotoFilter('none', 'Original', identityMatrix),
  PhotoFilter(
    'vivid',
    'Éclat',
    compose(saturationMatrix(0.4), contrastMatrix(0.15)),
  ),
  PhotoFilter('mono', 'Noir et blanc', saturationMatrix(-1)),
  PhotoFilter(
    'noir',
    'Film noir',
    compose(saturationMatrix(-1), contrastMatrix(0.4)),
  ),
  const PhotoFilter('sepia', 'Sépia', [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  PhotoFilter(
    'vintage',
    'Vintage',
    compose(
      compose(saturationMatrix(-0.25), warmthMatrix(0.45)),
      fadeMatrix(0.45),
    ),
  ),
  PhotoFilter(
    'cool',
    'Froid',
    compose(warmthMatrix(-0.7), saturationMatrix(0.1)),
  ),
  PhotoFilter(
    'warm',
    'Chaud',
    compose(warmthMatrix(0.7), saturationMatrix(0.1)),
  ),
  PhotoFilter(
    'faded',
    'Fané',
    compose(fadeMatrix(0.7), saturationMatrix(-0.2)),
  ),
  PhotoFilter(
    'drama',
    'Dramatique',
    compose(
      compose(contrastMatrix(0.4), saturationMatrix(-0.2)),
      brightnessMatrix(-0.05),
    ),
  ),
  PhotoFilter(
    'soft',
    'Doux',
    compose(
      compose(contrastMatrix(-0.15), brightnessMatrix(0.08)),
      saturationMatrix(-0.1),
    ),
  ),
  const PhotoFilter('negative', 'Négatif', [
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]),
];

PhotoFilter filterById(String id) => photoFilters.firstWhere(
  (f) => f.id == id,
  orElse: () => photoFilters.first,
);

/// A freehand stroke. Points are in the oriented image, from 0 to 1 on
/// both axes; [width] is a fraction of the image's shorter side.
class Stroke {
  const Stroke(this.color, this.width, this.points);
  final int color;
  final double width;
  final List<Offset> points;

  Stroke withPoint(Offset p) => Stroke(color, width, [...points, p]);
  Stroke mapped(Offset Function(Offset) f) =>
      Stroke(color, width, [for (final p in points) f(p)]);
}

/// A piece of text laid over the photo. [position] is the centre of the
/// text in the oriented image (0 to 1 on both axes); [size] is the text
/// height as a fraction of the image's shorter side.
class TextItem {
  const TextItem(
    this.text, {
    this.position = const Offset(0.5, 0.5),
    this.size = 0.07,
    this.color = 0xFFFFFFFF,
    this.bold = true,
    this.background = false,
  });

  final String text;
  final Offset position;
  final double size;
  final int color;
  final bool bold;

  /// Dark rounded box behind the text, for legibility.
  final bool background;

  TextItem copyWith({
    String? text,
    Offset? position,
    double? size,
    int? color,
    bool? bold,
    bool? background,
  }) => TextItem(
    text ?? this.text,
    position: position ?? this.position,
    size: size ?? this.size,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    background: background ?? this.background,
  );

  TextItem mapped(Offset Function(Offset) f) => copyWith(position: f(position));
}

/// Largest straightening, in degrees either way.
const maxStraighten = 45.0;

/// Zoom that keeps a frame of [width] × [height] fully covered by the photo
/// once the photo is turned by [degrees] around its centre: without it the
/// corners would show blank space.
double straightenScale(double width, double height, double degrees) {
  final a = degrees.abs() * math.pi / 180;
  if (a == 0 || width <= 0 || height <= 0) return 1;
  final long = math.max(width, height), short = math.min(width, height);
  return math.cos(a) + math.sin(a) * long / short;
}

/// Every edit made to a photo, kept apart from the image itself so that
/// nothing is ever destructive and any step can be undone.
class EditState {
  const EditState({
    this.quarterTurns = 0,
    this.flipped = false,
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
    this.adjust = const {},
    this.filter = 'none',
    this.intensity = 1,
    this.strokes = const [],
    this.straighten = 0,
    this.texts = const [],
  });

  /// Fine rotation in degrees (positive is clockwise), applied to the
  /// oriented picture; the picture is zoomed just enough to hide the corners.
  final double straighten;
  final List<TextItem> texts;

  /// Clockwise quarter turns, 0–3, applied after [flipped].
  final int quarterTurns;
  final bool flipped;

  /// Visible part of the oriented image, from 0 to 1.
  final Rect crop;
  final Map<Adjust, double> adjust;
  final String filter;
  final double intensity;
  final List<Stroke> strokes;

  double value(Adjust a) => adjust[a] ?? 0;

  bool get isCropped => crop != const Rect.fromLTWH(0, 0, 1, 1);

  bool get isUntouched =>
      quarterTurns == 0 &&
      !flipped &&
      !isCropped &&
      adjust.values.every((v) => v == 0) &&
      filter == 'none' &&
      strokes.isEmpty &&
      straighten == 0 &&
      texts.isEmpty;

  EditState copyWith({
    int? quarterTurns,
    bool? flipped,
    Rect? crop,
    Map<Adjust, double>? adjust,
    String? filter,
    double? intensity,
    List<Stroke>? strokes,
    double? straighten,
    List<TextItem>? texts,
  }) => EditState(
    quarterTurns: quarterTurns ?? this.quarterTurns,
    flipped: flipped ?? this.flipped,
    crop: crop ?? this.crop,
    adjust: adjust ?? this.adjust,
    filter: filter ?? this.filter,
    intensity: intensity ?? this.intensity,
    strokes: strokes ?? this.strokes,
    straighten: straighten ?? this.straighten,
    texts: texts ?? this.texts,
  );

  EditState withAdjust(Adjust a, double v) =>
      copyWith(adjust: {...adjust, a: v});

  /// Rotates the picture 90° clockwise, carrying crop and drawings along.
  EditState rotatedClockwise() => copyWith(
    quarterTurns: (quarterTurns + 1) % 4,
    crop: Rect.fromLTRB(1 - crop.bottom, crop.left, 1 - crop.top, crop.right),
    strokes: [for (final s in strokes) s.mapped((p) => Offset(1 - p.dy, p.dx))],
    texts: [for (final t in texts) t.mapped((p) => Offset(1 - p.dy, p.dx))],
  );

  /// Rotates 90° counter-clockwise.
  EditState rotatedCounterClockwise() =>
      rotatedClockwise().rotatedClockwise().rotatedClockwise();

  /// Mirrors the displayed picture left to right.
  EditState mirrored() => copyWith(
    // Mirroring reverses the rotation; the flip flag records it.
    quarterTurns: (4 - quarterTurns) % 4,
    flipped: !flipped,
    crop: Rect.fromLTRB(1 - crop.right, crop.top, 1 - crop.left, crop.bottom),
    strokes: [for (final s in strokes) s.mapped((p) => Offset(1 - p.dx, p.dy))],
    texts: [for (final t in texts) t.mapped((p) => Offset(1 - p.dx, p.dy))],
    straighten: -straighten,
  );

  /// Colour matrix of filter and adjustments, applied to the pixels.
  ColorMatrix get matrix {
    var m = identityMatrix;
    final e = value(Adjust.exposure) / 100;
    final t = value(Adjust.tint) / 100;
    final b = value(Adjust.brightness) / 100;
    final c = value(Adjust.contrast) / 100;
    final s = value(Adjust.saturation) / 100;
    final w = value(Adjust.warmth) / 100;
    final f = value(Adjust.fade) / 100;
    if (e != 0) m = compose(m, exposureMatrix(e));
    if (b != 0) m = compose(m, brightnessMatrix(b));
    if (c != 0) m = compose(m, contrastMatrix(c));
    if (s != 0) m = compose(m, saturationMatrix(s));
    if (w != 0) m = compose(m, warmthMatrix(w));
    if (t != 0) m = compose(m, tintMatrix(t));
    if (f != 0) m = compose(m, fadeMatrix(f));
    if (filter != 'none') {
      m = compose(m, blendWithIdentity(filterById(filter).matrix, intensity));
    }
    return m;
  }
}

/// Size of the picture once rotated, for a source of [width] × [height].
Size orientedSize(double width, double height, EditState s) =>
    s.quarterTurns.isOdd ? Size(height, width) : Size(width, height);

/// Crop rectangles that can be forced.
class CropRatio {
  const CropRatio(this.label, this.ratio);
  final String label;

  /// Width over height, or null for free. A ratio of 0 means "as the photo".
  final double? ratio;
}

const cropRatios = <CropRatio>[
  CropRatio('Libre', null),
  CropRatio('Original', 0),
  CropRatio('1:1', 1),
  CropRatio('4:3', 4 / 3),
  CropRatio('3:4', 3 / 4),
  CropRatio('16:9', 16 / 9),
  CropRatio('9:16', 9 / 16),
];

/// Largest centred crop with the pixel ratio [ratio] inside a picture of
/// [size], in normalised coordinates. A ratio of 0 keeps the whole photo.
Rect centeredCrop(double ratio, Size size) {
  final k = ratio == 0 ? 1.0 : ratio * size.height / size.width;
  final w = k >= 1 ? 1.0 : k;
  final h = k >= 1 ? 1 / k : 1.0;
  return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
}

const _minCrop = 0.08;

/// Crop rectangle after dragging the corner opposite to [anchor] to
/// [pointer]. [k] is the normalised width over height to keep, or null.
Rect dragCorner(Offset anchor, Offset pointer, double? k) {
  final sx = pointer.dx >= anchor.dx ? 1.0 : -1.0;
  final sy = pointer.dy >= anchor.dy ? 1.0 : -1.0;
  var w = (pointer.dx - anchor.dx).abs();
  var h = (pointer.dy - anchor.dy).abs();
  final availW = sx > 0 ? 1 - anchor.dx : anchor.dx;
  final availH = sy > 0 ? 1 - anchor.dy : anchor.dy;
  if (k == null) {
    w = math.min(math.max(w, _minCrop), availW);
    h = math.min(math.max(h, _minCrop), availH);
  } else {
    w = math.max(math.max(w, h * k), _minCrop);
    w = math.min(w, math.min(availW, availH * k));
    h = w / k;
  }
  return Rect.fromPoints(anchor, anchor + Offset(sx * w, sy * h));
}

/// [r] moved by [delta] but kept inside the picture.
Rect moveWithin(Rect r, Offset delta) {
  final dx = (r.left + delta.dx).clamp(0.0, 1 - r.width) - r.left;
  final dy = (r.top + delta.dy).clamp(0.0, 1 - r.height) - r.top;
  return r.shift(Offset(dx, dy));
}
