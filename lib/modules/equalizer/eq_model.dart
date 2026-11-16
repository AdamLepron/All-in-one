import 'dart:math' as math;

/// Bands shown before the device reports its own.
const defaultBands = <int>[60, 230, 910, 3600, 14000];

/// A named response curve as (frequency in Hz, gain in dB) points.
class EqPreset {
  const EqPreset(this.name, this.points);
  final String name;
  final List<(double, double)> points;
}

const eqPresets = <EqPreset>[
  EqPreset('Neutre', [(20, 0), (20000, 0)]),
  EqPreset('Basses +', [(40, 7), (120, 5), (400, 1), (1000, 0), (20000, 0)]),
  EqPreset('Aigus +', [(20, 0), (1000, 0), (4000, 3), (10000, 6), (16000, 7)]),
  EqPreset('Voix', [
    (60, -3),
    (250, 0),
    (1000, 3),
    (3000, 4),
    (8000, 1),
    (16000, -1),
  ]),
  EqPreset('Rock', [
    (60, 5),
    (250, 2),
    (900, -2),
    (3500, 2),
    (10000, 5),
    (16000, 5),
  ]),
  EqPreset('Pop', [
    (60, -1),
    (250, 2),
    (1000, 4),
    (3500, 2),
    (10000, -1),
    (16000, -2),
  ]),
  EqPreset('Jazz', [
    (60, 3),
    (250, 1),
    (1000, -1),
    (3500, 1),
    (10000, 3),
    (16000, 4),
  ]),
  EqPreset('Classique', [
    (60, 4),
    (250, 2),
    (1000, 0),
    (3500, 1),
    (10000, 3),
    (16000, 4),
  ]),
  EqPreset('Électro', [
    (50, 6),
    (200, 3),
    (800, -1),
    (2500, 1),
    (8000, 4),
    (16000, 5),
  ]),
  EqPreset('Loudness', [(50, 6), (200, 2), (1000, 0), (4000, 1), (12000, 5)]),
];

/// Gain of the curve [points] at [hz], interpolated on a logarithmic
/// frequency axis and held flat beyond its ends.
double levelAt(List<(double, double)> points, double hz) {
  if (points.isEmpty) return 0;
  if (hz <= points.first.$1) return points.first.$2;
  if (hz >= points.last.$1) return points.last.$2;
  for (var i = 1; i < points.length; i++) {
    final (f1, g1) = points[i - 1];
    final (f2, g2) = points[i];
    if (hz <= f2) {
      final t = (math.log(hz) - math.log(f1)) / (math.log(f2) - math.log(f1));
      return g1 + (g2 - g1) * t;
    }
  }
  return points.last.$2;
}

/// Levels of a curve on the given bands, rounded to half a dB and kept
/// within the device range.
List<double> levelsFor(
  List<(double, double)> points,
  List<int> bands, {
  double min = -15,
  double max = 15,
}) => [
  for (final hz in bands)
    ((levelAt(points, hz.toDouble()) * 2).round() / 2)
        .clamp(min, max)
        .toDouble(),
];

/// "60", "910", "3,6k", "14k".
String bandLabel(int hz) {
  if (hz < 1000) return '$hz';
  final k = hz / 1000;
  return k >= 10 || k == k.roundToDouble()
      ? '${k.round()}k'
      : '${k.toStringAsFixed(1).replaceAll('.', ',')}k';
}
