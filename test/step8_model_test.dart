import 'dart:ui';

import 'package:all_in_one/modules/photo/edit_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies a matrix to an RGB colour on the 0–255 scale.
List<double> apply(List<double> m, double r, double g, double b) => [
  for (var row = 0; row < 3; row++)
    (m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4])
        .clamp(0, 255),
];

void main() {
  test('compose applies the first matrix then the second', () {
    final both = compose(brightnessMatrix(0.5), contrastMatrix(1));
    // 100 → +50 brightness = 150 → contrast ×2 around 128 = 172.
    expect(apply(both, 100, 100, 100)[0], closeTo(172, 1e-9));
    final other = compose(contrastMatrix(1), brightnessMatrix(0.5));
    // 100 → 72 → +50 = 122.
    expect(apply(other, 100, 100, 100)[0], closeTo(122, 1e-9));
    expect(
      compose(identityMatrix, saturationMatrix(0.3)),
      saturationMatrix(0.3),
    );
  });

  test('basic matrices', () {
    expect(apply(brightnessMatrix(0), 10, 20, 30), [10, 20, 30]);
    expect(apply(contrastMatrix(0), 10, 20, 30), [10, 20, 30]);
    final grey = apply(saturationMatrix(-1), 200, 50, 10);
    expect(grey[0], closeTo(grey[1], 1e-9));
    expect(grey[1], closeTo(grey[2], 1e-9));
    // Neutral greys are untouched by saturation.
    expect(apply(saturationMatrix(0.8), 90, 90, 90)[0], closeTo(90, 1e-9));
    final warm = apply(warmthMatrix(1), 100, 100, 100);
    expect(warm[0], greaterThan(warm[2]));
    expect(apply(fadeMatrix(1), 0, 0, 0)[0], greaterThan(30)); // blacks lifted
    expect(apply(photoFilters.last.matrix, 255, 0, 40), [
      0,
      255,
      215,
    ]); // negative
    expect(blendWithIdentity(photoFilters.last.matrix, 0), identityMatrix);
  });

  test('edit state matrix and untouched detection', () {
    const base = EditState();
    expect(base.isUntouched, true);
    expect(base.matrix, identityMatrix);
    final edited = base
        .withAdjust(Adjust.brightness, 40)
        .copyWith(filter: 'sepia', intensity: 0.5);
    expect(edited.isUntouched, false);
    expect(edited.matrix, isNot(identityMatrix));
    expect(base.withAdjust(Adjust.warmth, 0).isUntouched, true);
    // Filter intensity 0 is no filter at all.
    expect(base.copyWith(filter: 'sepia', intensity: 0).matrix, identityMatrix);
  });

  test('rotation carries crop and drawings along', () {
    const crop = Rect.fromLTRB(0, 0, 0.5, 0.25); // top-left corner
    final state = const EditState().copyWith(
      crop: crop,
      strokes: [
        const Stroke(0xFFFF0000, 0.01, [Offset(0, 0), Offset(0.5, 0.25)]),
      ],
    );
    final turned = state.rotatedClockwise();
    expect(turned.quarterTurns, 1);
    // The top-left corner goes to the top-right.
    expect(turned.crop, const Rect.fromLTRB(0.75, 0, 1, 0.5));
    expect(turned.strokes.single.points, const [
      Offset(1, 0),
      Offset(0.75, 0.5),
    ]);
    // Four turns bring everything back.
    var s = state;
    for (var i = 0; i < 4; i++) {
      s = s.rotatedClockwise();
    }
    expect(s.quarterTurns, 0);
    expect(s.crop, crop);
    expect(s.strokes.single.points, state.strokes.single.points);
    expect(state.rotatedCounterClockwise().rotatedClockwise().crop, crop);
  });

  test('mirroring flips crop and drawings and is its own inverse', () {
    final state = const EditState().copyWith(
      quarterTurns: 1,
      crop: const Rect.fromLTRB(0, 0.1, 0.4, 0.5),
      strokes: [
        const Stroke(0xFF000000, 0.01, [Offset(0.1, 0.2)]),
      ],
    );
    final m = state.mirrored();
    expect(m.flipped, true);
    expect(m.quarterTurns, 3);
    expect(m.crop, const Rect.fromLTRB(0.6, 0.1, 1, 0.5));
    expect(m.strokes.single.points.single.dx, closeTo(0.9, 1e-12));
    final back = m.mirrored();
    expect(back.flipped, false);
    expect(back.quarterTurns, 1);
    expect(back.crop, state.crop);
  });

  test('oriented size swaps on odd turns', () {
    expect(orientedSize(400, 300, const EditState()), const Size(400, 300));
    expect(
      orientedSize(400, 300, const EditState(quarterTurns: 3)),
      const Size(300, 400),
    );
  });

  test('crop ratios', () {
    // 4:3 landscape picture, square crop: full height, 3/4 of the width.
    final square = centeredCrop(1, const Size(400, 300));
    expect(square.width, closeTo(0.75, 1e-12));
    expect(square.height, 1);
    expect(square.center, const Offset(0.5, 0.5));
    expect(
      centeredCrop(0, const Size(400, 300)),
      const Rect.fromLTWH(0, 0, 1, 1),
    );
    final wide = centeredCrop(16 / 9, const Size(300, 400));
    expect(wide.width, 1);
    expect(wide.width * 300 / (wide.height * 400), closeTo(16 / 9, 1e-9));
  });

  test('corner dragging', () {
    // Free drag, clamped to the picture and to a minimum size.
    final free = dragCorner(
      const Offset(0.2, 0.2),
      const Offset(1.4, 0.9),
      null,
    );
    expect(free.left, closeTo(0.2, 1e-9));
    expect(free.top, closeTo(0.2, 1e-9));
    expect(free.right, closeTo(1, 1e-9));
    expect(free.bottom, closeTo(0.9, 1e-9));
    final tiny = dragCorner(
      const Offset(0.5, 0.5),
      const Offset(0.5, 0.5),
      null,
    );
    expect(tiny.width, closeTo(0.08, 1e-9));
    // Locked ratio keeps width / height = k wherever the pointer goes.
    for (final p in const [
      Offset(0.9, 0.6),
      Offset(0.3, 0.95),
      Offset(0.05, 0.05),
      Offset(2, 2),
    ]) {
      final r = dragCorner(const Offset(0.4, 0.4), p, 1.5);
      expect(r.width / r.height, closeTo(1.5, 1e-9), reason: '$p');
      expect(r.left, greaterThanOrEqualTo(-1e-9));
      expect(r.right, lessThanOrEqualTo(1 + 1e-9));
      expect(r.top, greaterThanOrEqualTo(-1e-9));
      expect(r.bottom, lessThanOrEqualTo(1 + 1e-9));
    }
    expect(
      moveWithin(
        const Rect.fromLTWH(0.5, 0.5, 0.4, 0.4),
        const Offset(0.5, -2),
      ),
      const Rect.fromLTWH(0.6, 0, 0.4, 0.4),
    );
  });
}
