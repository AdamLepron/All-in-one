import 'dart:io';
import 'dart:typed_data';

import 'package:all_in_one/modules/cleaner/blur.dart';
import 'package:all_in_one/modules/cleaner/cleaner_scan.dart';
import 'package:flutter_test/flutter_test.dart';

/// RGBA picture of [w]×[h] from a grey-level function.
Uint8List picture(int w, int h, int Function(int x, int y) grey) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final g = grey(x, y);
      out[o] = out[o + 1] = out[o + 2] = g;
      out[o + 3] = 255;
    }
  }
  return out;
}

void main() {
  group('blur score', () {
    test('a flat picture and a smooth gradient score near zero', () {
      expect(laplacianVariance(picture(64, 64, (_, _) => 120), 64, 64), 0);
      final gradient = picture(64, 64, (x, _) => x * 4);
      expect(laplacianVariance(gradient, 64, 64), lessThan(1));
    });

    test('a sharp checkerboard scores far higher than a blurred one', () {
      final sharp = picture(
        64,
        64,
        (x, y) => (x ~/ 2 + y ~/ 2).isEven ? 0 : 255,
      );
      // The same pattern averaged over a 4×4 neighbourhood.
      final blurred = picture(64, 64, (x, y) {
        var sum = 0;
        var n = 0;
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final xx = (x + dx).clamp(0, 63), yy = (y + dy).clamp(0, 63);
            sum += (xx ~/ 2 + yy ~/ 2).isEven ? 0 : 255;
            n++;
          }
        }
        return sum ~/ n;
      });
      final s = laplacianVariance(sharp, 64, 64);
      final b = laplacianVariance(blurred, 64, 64);
      expect(s, greaterThan(blurThreshold * 10));
      expect(b, lessThan(s / 10));
    });

    test('tiny pictures cannot be judged', () {
      expect(laplacianVariance(Uint8List(8), 2, 2), double.infinity);
    });
  });

  group('cleaner categories', () {
    late Directory root;
    final now = DateTime(2030, 6, 1);
    File put(String rel, {int bytes = 30000, DateTime? modified}) {
      final f = File('${root.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(bytes, 1));
      if (modified != null) f.setLastModifiedSync(modified);
      return f;
    }

    setUp(() => root = Directory.systemTemp.createTempSync('step16_clean'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'blurry photos: only camera pictures below the limit, never ticked',
      () async {
        put('DCIM/Camera/net.jpg', modified: DateTime(2030, 5, 30));
        put('DCIM/Camera/flou.jpg', modified: DateTime(2030, 5, 29));
        put('Pictures/Screenshots/capture.png');
        put('Download/image.jpg'); // not a camera folder
        put('DCIM/Camera/petit.jpg', bytes: 100); // too small to be a photo
        final asked = <String>[];
        final report = await analyzeStorage(
          root.path,
          now: now,
          blurScore: (path) async {
            asked.add(path.split('/').last);
            return path.endsWith('flou.jpg') ? 5 : 500;
          },
        );
        final blurry = report.items[CleanCategory.blurry]!;
        expect(blurry.map((i) => i.name), ['flou.jpg']);
        expect(blurry.single.preselected, isFalse);
        expect(asked.toSet(), {'net.jpg', 'flou.jpg'});
        expect(report.gain(CleanCategory.blurry), 0); // nothing ticked
      },
    );

    test(
      'unreadable pictures are not called blurry; no scorer, no check',
      () async {
        put('DCIM/a.jpg');
        final r1 = await analyzeStorage(
          root.path,
          now: now,
          blurScore: (_) async => null,
        );
        expect(r1.items[CleanCategory.blurry], isEmpty);
        final r2 = await analyzeStorage(root.path, now: now);
        expect(r2.items[CleanCategory.blurry], isEmpty);
      },
    );

    test('the number of pictures checked is limited, newest first', () async {
      for (var i = 0; i < 5; i++) {
        put('DCIM/p$i.jpg', modified: DateTime(2030, 5, 1 + i));
      }
      final asked = <String>[];
      await analyzeStorage(
        root.path,
        now: now,
        maxPhotosChecked: 2,
        blurScore: (path) async {
          asked.add(path.split('/').last);
          return 100;
        },
      );
      expect(asked, ['p4.jpg', 'p3.jpg']);
    });

    test(
      'messaging media: old received files only, found under Android/media',
      () async {
        const wa = 'Android/media/com.whatsapp/WhatsApp/Media';
        put('$wa/WhatsApp Images/IMG-old.jpg', modified: DateTime(2030, 1, 1));
        put(
          '$wa/WhatsApp Images/IMG-recent.jpg',
          modified: DateTime(2030, 5, 20),
        );
        put(
          '$wa/WhatsApp Images/Sent/IMG-mine.jpg',
          modified: DateTime(2030, 1, 1),
        );
        put('$wa/WhatsApp Video/VID-old.mp4', modified: DateTime(2030, 2, 1));
        put('$wa/WhatsApp Images/.nomedia', modified: DateTime(2030, 1, 1));
        put(
          'Telegram/Telegram Documents/doc.pdf',
          modified: DateTime(2030, 1, 1),
        );
        put('Android/data/autre/x.jpg', modified: DateTime(2030, 1, 1));
        final report = await analyzeStorage(root.path, now: now);
        final names = report.items[CleanCategory.messaging]!
            .map((i) => i.name)
            .toSet();
        expect(names, {'IMG-old.jpg', 'VID-old.mp4', 'doc.pdf'});
        expect(
          report.items[CleanCategory.messaging]!.every((i) => !i.preselected),
          isTrue,
        );
      },
    );

    test('folders listed for the messaging apps', () {
      final f = messagingFolders('/storage/emulated/0');
      expect(
        f,
        contains(
          '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media',
        ),
      );
      expect(f, contains('/storage/emulated/0/Telegram'));
    });
  });
}
