import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:all_in_one/modules/photo/edit_model.dart';
import 'package:all_in_one/modules/photo/edit_render.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('straightening', () {
    test('no zoom when level; more zoom for a bigger angle', () {
      expect(straightenScale(400, 300, 0), 1);
      final small = straightenScale(400, 300, 3);
      final big = straightenScale(400, 300, 20);
      expect(small, greaterThan(1));
      expect(big, greaterThan(small));
      // Sign does not matter.
      expect(straightenScale(400, 300, -20), closeTo(big, 1e-9));
    });

    test('the zoomed photo covers every corner of the frame', () {
      for (final (w, h) in [(400.0, 300.0), (300.0, 400.0), (500.0, 500.0)]) {
        for (final deg in [1.0, 7.5, 15.0, 30.0, 45.0]) {
          final s = straightenScale(w, h, deg);
          final a = deg * math.pi / 180;
          // Corners of the frame, seen from the turned photo's own axes:
          // they must lie within the (scaled) photo's half sizes.
          for (final sx in [-1.0, 1.0]) {
            for (final sy in [-1.0, 1.0]) {
              final x = sx * w / 2, y = sy * h / 2;
              final px = x * math.cos(a) + y * math.sin(a);
              final py = -x * math.sin(a) + y * math.cos(a);
              expect(px.abs(), lessThanOrEqualTo(s * w / 2 + 1e-6));
              expect(py.abs(), lessThanOrEqualTo(s * h / 2 + 1e-6));
            }
          }
        }
      }
    });

    test('mirroring reverses the angle; turns keep it; untouched checks', () {
      const s = EditState(straighten: 10);
      expect(s.mirrored().straighten, -10);
      expect(s.rotatedClockwise().straighten, 10);
      expect(s.isUntouched, isFalse);
      expect(const EditState().isUntouched, isTrue);
      expect(const EditState(texts: [TextItem('a')]).isUntouched, isFalse);
    });
  });

  test('texts move with rotations and mirroring like drawings do', () {
    const s = EditState(texts: [TextItem('Salut', position: Offset(0.2, 0.1))]);
    final turned = s.rotatedClockwise().texts.single.position;
    expect(turned.dx, closeTo(0.9, 1e-9));
    expect(turned.dy, closeTo(0.2, 1e-9));
    final back = s
        .rotatedClockwise()
        .rotatedCounterClockwise()
        .texts
        .single
        .position;
    expect(back.dx, closeTo(0.2, 1e-9));
    expect(back.dy, closeTo(0.1, 1e-9));
    final mirrored = s.mirrored().texts.single.position;
    expect(mirrored.dx, closeTo(0.8, 1e-9));
    expect(mirrored.dy, closeTo(0.1, 1e-9));
    expect(s.texts.single.copyWith(size: 0.1).size, 0.1);
  });

  group('new adjustments', () {
    test('exposure brightens and darkens by powers of two', () {
      final up = exposureMatrix(1);
      final down = exposureMatrix(-1);
      expect(up[0], closeTo(math.pow(2, 1.5), 1e-9));
      expect(down[0], closeTo(math.pow(2, -1.5), 1e-9));
      expect(exposureMatrix(0), identityMatrix);
    });

    test('tint moves green against red and blue', () {
      final m = tintMatrix(1);
      expect(m[6], lessThan(1)); // less green
      expect(m[0], greaterThan(1));
      expect(tintMatrix(-1)[6], greaterThan(1));
      expect(tintMatrix(0), identityMatrix);
    });

    test('they feed the colour matrix, and only when used', () {
      expect(const EditState().matrix, identityMatrix);
      final e = const EditState().withAdjust(Adjust.exposure, 50).matrix;
      expect(e[0], greaterThan(1));
      final t = const EditState().withAdjust(Adjust.tint, 50).matrix;
      expect(t[6], lessThan(1));
      // Order of the sliders in the panel: exposure first.
      expect(Adjust.values.first, Adjust.exposure);
    });
  });

  group('export options', () {
    test('size is scaled down to the chosen longest side, never up', () {
      const o = ExportOptions(maxSide: 1000);
      expect(o.scaled(const Size(4000, 3000)), const Size(1000, 750));
      expect(o.scaled(const Size(3000, 4000)), const Size(750, 1000));
      expect(o.scaled(const Size(800, 600)), const Size(800, 600));
      expect(
        const ExportOptions().scaled(const Size(4000, 3000)),
        const Size(4000, 3000),
      );
      expect(const ExportOptions(png: true).extension, 'png');
      expect(const ExportOptions().extension, 'jpg');
    });
  });

  group('rendering', () {
    late Directory tmp;
    late String source;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('step15_photo');
      // 80 × 60, all red: any blank corner would show as white.
      final image = img.Image(width: 80, height: 60)
        ..clear(img.ColorRgb8(255, 0, 0));
      source = '${tmp.path}/in.png';
      await File(source).writeAsBytes(img.encodePng(image));
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<img.Image> edit(EditState s, {ExportOptions? options}) async {
      final path = await saveEditedCopy(
        source,
        s,
        dir: '${tmp.path}/out',
        options: options ?? const ExportOptions(),
      );
      return img.decodeImage(
        Uint8List.fromList(await File(path).readAsBytes()),
      )!;
    }

    bool red(img.Pixel p) => p.r > 200 && p.g < 80 && p.b < 80;

    testWidgets('a straightened photo has no blank corners', (tester) async {
      await tester.runAsync(() async {
        final out = await edit(
          const EditState(straighten: 12),
          options: const ExportOptions(png: true),
        );
        expect((out.width, out.height), (80, 60));
        for (final (x, y) in [(0, 0), (79, 0), (0, 59), (79, 59), (40, 30)]) {
          expect(red(out.getPixel(x, y)), isTrue, reason: 'pixel $x,$y');
        }
      });
    });

    testWidgets('PNG and size options change the file', (tester) async {
      await tester.runAsync(() async {
        final png = await edit(
          const EditState(),
          options: const ExportOptions(png: true),
        );
        expect((png.width, png.height), (80, 60));
        final small = await edit(
          const EditState(),
          options: const ExportOptions(maxSide: 40),
        );
        expect((small.width, small.height), (40, 30));
        final files = Directory('${tmp.path}/out')
            .listSync()
            .map((f) => f.path)
            .toList();
        expect(files.any((f) => f.endsWith('.png')), isTrue);
        expect(files.any((f) => f.endsWith('.jpg')), isTrue);
      });
    });

    testWidgets('text is drawn where it was placed', (tester) async {
      await tester.runAsync(() async {
        final plain = await edit(
          const EditState(),
          options: const ExportOptions(png: true),
        );
        final withText = await edit(
          const EditState(
            texts: [
              TextItem(
                'MM',
                position: Offset(0.5, 0.5),
                size: 0.15,
                color: 0xFFFFFFFF,
                background: true,
              ),
            ],
          ),
          options: const ExportOptions(png: true),
        );
        // The centre changed (a dark box and white letters), the far corner did not.
        expect(red(plain.getPixel(40, 30)), isTrue);
        expect(red(withText.getPixel(40, 30)), isFalse);
        expect(red(withText.getPixel(1, 1)), isTrue);
      });
    });
  });
}
