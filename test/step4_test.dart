import 'dart:io';

import 'package:all_in_one/modules/equalizer/eq_model.dart';
import 'package:all_in_one/modules/reader/documents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equaliser curves interpolate on a log frequency axis', () {
    const curve = [(100.0, 0.0), (10000.0, 10.0)];
    expect(levelAt(curve, 50), 0); // flat before the first point
    expect(levelAt(curve, 20000), 10); // flat after the last
    expect(levelAt(curve, 1000), closeTo(5, 1e-9)); // geometric middle
    expect(levelsFor(curve, [100, 1000, 10000]), [0, 5, 10]);
    expect(levelsFor(curve, [10000], max: 6), [6]); // clamped to the device
    expect(levelsFor(eqPresets.first.points, defaultBands), everyElement(0));
    for (final preset in eqPresets) {
      final freqs = preset.points.map((p) => p.$1).toList();
      expect(freqs, orderedEquals([...freqs]..sort()), reason: preset.name);
    }
  });

  test('band labels', () {
    expect(bandLabel(60), '60');
    expect(bandLabel(3600), '3,6k');
    expect(bandLabel(14000), '14k');
    expect(bandLabel(1000), '1k');
  });

  test(
    'document scan finds documents and skips hidden and system folders',
    () async {
      final tmp = await Directory.systemTemp.createTemp('scan_test');
      addTearDown(() => tmp.delete(recursive: true));
      Future<void> file(String rel) async {
        final f = File('${tmp.path}/$rel');
        await f.parent.create(recursive: true);
        await f.writeAsString('x');
      }

      await file('a.pdf');
      await file('Download/sub/b.txt');
      await file('Download/photo.jpg');
      await file('.cache/c.pdf');
      await file('Android/data/d.pdf');
      await file(
        'Docs/Android/e.docx',
      ); // only the top-level Android is skipped

      final names = (await scanDocuments(tmp.path)).map((d) => d.name).toSet();
      expect(names, {'a.pdf', 'b.txt', 'e.docx'});
      expect(docTypeOf('x/A.PDF'), DocType.pdf);
      expect(docTypeOf('notes.md'), DocType.text);
      expect(docTypeOf('cv.docx'), DocType.other);
    },
  );
}
