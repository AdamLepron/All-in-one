import 'dart:io';

import 'package:all_in_one/modules/cleaner/cleaner_scan.dart';
import 'package:all_in_one/modules/files/file_ops.dart';
import 'package:all_in_one/modules/scanner/scan_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  String at(String rel) => p.join(tmp.path, rel);

  Future<File> file(String rel, String content, {int ageDays = 0}) async {
    final f = File(at(rel));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
    if (ageDays > 0) {
      await f.setLastModified(DateTime.now().subtract(Duration(days: ageDays)));
    }
    return f;
  }

  setUp(() async => tmp = await Directory.systemTemp.createTemp('step7'));
  tearDown(() => tmp.delete(recursive: true));

  test('storage analysis sorts files into the right categories', () async {
    await file('Photos/a.jpg', 'same content', ageDays: 10);
    await file('Photos/copie/a (1).jpg', 'same content', ageDays: 2);
    await file('Download/a-encore.jpg', 'same content', ageDays: 1);
    await file('Photos/b.jpg', 'same length!'); // same size, other content
    await file('Download/vieux.pdf', 'old download', ageDays: 200);
    await file('Download/recent.pdf', 'new download', ageDays: 3);
    await file('Pictures/Screenshots/s1.png', 'shot one', ageDays: 60);
    await file('Pictures/Screenshots/s2.png', 'shot two', ageDays: 5);
    await file('Download/app.apk', 'apk');
    await file('cache.tmp', 'tmp');
    await file('Android/data/x/huge.tmp', 'ignored');
    await file('.AllInOneTrash/1', 'ignored too');
    await Directory(at('Vide')).create();

    final report = await analyzeStorage(tmp.path);
    List<String> names(CleanCategory c) =>
        report.items[c]!.map((i) => p.basename(i.path)).toList()..sort();

    // Three identical files: the oldest is kept, the two others offered.
    final dup = report.items[CleanCategory.duplicates]!;
    expect(dup.map((i) => i.name).toSet(), {
      'a.jpg',
      'a (1).jpg',
      'a-encore.jpg',
    });
    expect(dup.where((i) => !i.preselected).single.name, 'a.jpg');
    expect(dup.map((i) => i.group).toSet().length, 1);

    expect(names(CleanCategory.oldDownloads), ['vieux.pdf']);
    expect(names(CleanCategory.screenshots), ['s1.png']);
    expect(names(CleanCategory.apks), ['app.apk']);
    expect(names(CleanCategory.junk), ['Vide', 'cache.tmp']);
    expect(report.items[CleanCategory.large], isEmpty);

    // Each file counts once even if it sits in two categories.
    final expected =
        2 * 'same content'.length +
        'old download'.length +
        'shot one'.length +
        3 +
        3;
    expect(report.totalGain, expected);
    expect(report.gain(CleanCategory.duplicates), 2 * 'same content'.length);
  });

  test('cleaning moves files to the recycle bin and can be undone', () async {
    final f = await file('Download/app.apk', 'apk');
    await Directory(at('Vide')).create();
    final trash = Trash(at('.AllInOneTrash'));
    final moved = await cleanToTrash([f.path, at('Vide'), at('absent')], trash);
    expect(moved, 2);
    expect(f.existsSync(), false);
    final item = (await trash.items()).firstWhere((i) => i.name == 'app.apk');
    await trash.restore(item);
    expect(f.existsSync(), true);
    // The bin itself is never offered for cleaning.
    final report = await analyzeStorage(tmp.path);
    expect(report.items[CleanCategory.junk], isEmpty);
  });

  test('scan titles and library', () async {
    final date = DateTime(2026, 11, 17, 9, 5);
    expect(scanTitle('', date), 'Scan du 17-11-2026 09h05');
    expect(
      scanTitle('12\n--\nFACTURE N° 2026/041\nMontant', date),
      'FACTURE N° 2026 041',
    );
    expect(
      scanTitle('a' * 60, date).length,
      41,
    ); // 40 characters and an ellipsis
    expect(localPath('file:///data/x/page%201.jpg'), '/data/x/page 1.jpg');
    expect(localPath('/data/x/p.jpg'), '/data/x/p.jpg');

    final image = await file('in/page.jpg', 'jpeg bytes');
    final pdf = await file('in/doc.pdf', 'pdf bytes');
    final store = ScanStore(directory: () async => at('scans'));
    final scan = await store.add(
      images: [image.path, image.path],
      pdf: 'file://${pdf.path}',
      text: 'Contrat de location\nEntre les soussignés',
    );
    expect(scan.title, 'Contrat de location');
    expect(scan.pages, 2);
    expect(File(scan.page(1)).existsSync(), true);
    expect(File(scan.pdf).readAsStringSync(), 'pdf bytes');

    expect(store.search('soussignés').single.title, 'Contrat de location');
    expect(store.search('facture'), isEmpty);
    await store.rename(scan, 'Bail 2026');
    await store.load(); // survives a reload
    expect(store.scans.single.title, 'Bail 2026');
    await store.delete(store.scans.single);
    expect(store.scans, isEmpty);
  });
}
