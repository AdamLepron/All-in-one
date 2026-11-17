import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:all_in_one/modules/photo/edit_model.dart';
import 'package:all_in_one/modules/photo/edit_render.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A 40×20 picture: left half red, right half blue.
Uint8List sampleJpeg() {
  final image = img.Image(width: 40, height: 20);
  for (final p in image) {
    p.setRgb(p.x < 20 ? 255 : 0, 0, p.x < 20 ? 0 : 255);
  }
  return img.encodePng(image);
}

/// Decodes JPEG or PNG bytes to (width, height, pixel accessor).
(int, int, List<int> Function(int, int)) decode(Uint8List bytes) {
  final image = img.decodeImage(bytes)!;
  return (
    image.width,
    image.height,
    (x, y) {
      final p = image.getPixel(x, y);
      return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
    },
  );
}

void main() {
  late Directory tmp;
  late String source;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('render_test');
    source = '${tmp.path}/in.png';
    await File(source).writeAsBytes(sampleJpeg());
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<(int, int, List<int> Function(int, int))> edit(EditState s) async {
    final dir = '${tmp.path}/out';
    final path = await saveEditedCopy(source, s, dir: dir);
    return decode(await File(path).readAsBytes());
  }

  bool near(List<int> c, List<int> e, [int tol = 40]) =>
      List.generate(3, (i) => (c[i] - e[i]).abs() <= tol).every((b) => b);

  testWidgets('export applies rotation, flip, crop and colour', (tester) async {
    await tester.runAsync(() async {
      // Untouched: same size, red left, blue right.
      var (w, h, px) = await edit(const EditState());
      expect((w, h), (40, 20));
      expect(near(px(5, 10), [255, 0, 0]), true);
      expect(near(px(35, 10), [0, 0, 255]), true);

      // Quarter turn clockwise: 20 × 40, red on top, blue at the bottom.
      (w, h, px) = await edit(const EditState().rotatedClockwise());
      expect((w, h), (20, 40));
      expect(near(px(10, 5), [255, 0, 0]), true);
      expect(near(px(10, 35), [0, 0, 255]), true);

      // Mirror: blue on the left.
      (w, h, px) = await edit(const EditState().mirrored());
      expect((w, h), (40, 20));
      expect(near(px(5, 10), [0, 0, 255]), true);

      // Mirror then rotate must equal what the model says it means.
      (w, h, px) = await edit(const EditState().mirrored().rotatedClockwise());
      expect((w, h), (20, 40));
      expect(near(px(10, 5), [0, 0, 255]), true); // blue is now on top

      // Crop to the right half only.
      (w, h, px) = await edit(
        const EditState(crop: ui.Rect.fromLTWH(0.5, 0, 0.5, 1)),
      );
      expect((w, h), (20, 20));
      expect(near(px(10, 10), [0, 0, 255]), true);
      expect(near(px(0, 0), [0, 0, 255]), true);

      // Black and white: red and blue become the same kind of grey.
      (w, h, px) = await edit(const EditState(filter: 'mono'));
      final grey = px(5, 10);
      expect(
        (grey[0] - grey[1]).abs() < 6 && (grey[1] - grey[2]).abs() < 6,
        true,
      );

      // Brightness raises every channel.
      (w, h, px) = await edit(
        const EditState().withAdjust(Adjust.brightness, 100),
      );
      expect(px(5, 10)[1], greaterThan(60));

      // A stroke in the middle of the picture leaves a green mark.
      (w, h, px) = await edit(
        const EditState(
          strokes: [
            Stroke(0xFF00FF00, 0.4, [Offset(0.5, 0.5)]),
          ],
        ),
      );
      expect(near(px(20, 10), [0, 255, 0], 60), true);
      expect(near(px(2, 2), [255, 0, 0]), true);
    });
  });

  testWidgets('copies never overwrite the original or each other', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final before = await File(source).readAsBytes();
      final dir = '${tmp.path}/out';
      final a = await saveEditedCopy(source, const EditState(), dir: dir);
      final b = await saveEditedCopy(source, const EditState(), dir: dir);
      expect(a, isNot(b));
      expect(await File(source).readAsBytes(), before);
      expect(Directory(dir).listSync().length, 2);
    });
  });

  testWidgets('loading respects the size limit', (tester) async {
    await tester.runAsync(() async {
      final big = img.Image(width: 400, height: 200);
      await File('${tmp.path}/big.png').writeAsBytes(img.encodePng(big));
      final small = await loadPhoto('${tmp.path}/big.png', maxSide: 100);
      expect((small.width, small.height), (100, 50));
      final full = await loadPhoto('${tmp.path}/big.png', maxSide: 4096);
      expect((full.width, full.height), (400, 200));
      expect(
        outputSize(full, const EditState(quarterTurns: 1)),
        const ui.Size(200, 400),
      );
    });
  });
}
