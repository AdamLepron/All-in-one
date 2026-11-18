import 'dart:io';

import 'package:all_in_one/modules/files/archives.dart';
import 'package:all_in_one/modules/files/categories.dart';
import 'package:all_in_one/modules/files/file_ops.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  String at(String rel) => '${tmp.path}/$rel';
  File write(String rel, String content, {DateTime? modified}) {
    final f = File(at(rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('step14'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('archives', () {
    test('entry names are made safe', () {
      expect(safeEntryName('a/b.txt'), 'a/b.txt');
      expect(safeEntryName('./a//b.txt'), 'a/b.txt');
      expect(safeEntryName(r'a\b.txt'), 'a/b.txt');
      expect(safeEntryName('../evil.txt'), isNull);
      expect(safeEntryName('a/../../evil.txt'), isNull);
      expect(safeEntryName('/etc/passwd'), isNull);
      expect(safeEntryName(r'C:\win.ini'), isNull);
      expect(safeEntryName(''), isNull);
      expect(safeEntryName('./'), isNull);
    });

    test('format detection and names', () {
      expect(canExtract('/x/a.ZIP'), isTrue);
      expect(canExtract('/x/a.tar.gz'), isTrue);
      expect(canExtract('/x/a.tgz'), isTrue);
      expect(canExtract('/x/a.rar'), isFalse);
      expect(canExtract('/x/a.7z'), isFalse);
      expect(archiveStem('/x/photos.tar.gz'), 'photos');
      expect(archiveStem('/x/Vacances.ZIP'), 'Vacances');
    });

    test('zip then extract round trip', () async {
      write('src/dossier/a.txt', 'alpha');
      write('src/dossier/sous/b.txt', 'beta é');
      Directory(at('src/vide')).createSync();
      write('src/seul.txt', 'seul');
      Directory(at('out')).createSync();
      final zip = await zipEntities(
        [at('src/dossier'), at('src/seul.txt'), at('src/vide')],
        at('out'),
        name: 'lot',
      );
      expect(zip, at('out/lot.zip'));
      expect(File('$zip.part').existsSync(), isFalse);

      // A second archive of the same name gets a free name.
      final again = await zipEntities(
        [at('src/seul.txt')],
        at('out'),
        name: 'lot',
      );
      expect(again, isNot(zip));

      final r = await extractArchive(zip, at('dest'));
      expect(r.files, 3);
      expect(r.skipped, 0);
      expect(File(at('dest/dossier/a.txt')).readAsStringSync(), 'alpha');
      expect(File(at('dest/dossier/sous/b.txt')).readAsStringSync(), 'beta é');
      expect(File(at('dest/seul.txt')).readAsStringSync(), 'seul');
      expect(Directory(at('dest/vide')).existsSync(), isTrue);
    });

    test('extraction never overwrites and refuses names that escape', () async {
      // Built by hand: a zip with a hostile entry.
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('ok.txt', [111, 107]))
        ..addFile(ArchiveFile.bytes('../evil.txt', [1]))
        ..addFile(ArchiveFile.bytes('/abs.txt', [2]));
      File(at('bad.zip')).writeAsBytesSync(ZipEncoder().encode(archive));
      write('dest/ok.txt', 'déjà là');
      final r = await extractArchive(at('bad.zip'), at('dest'));
      expect(r.files, 1);
      expect(r.skipped, 2);
      expect(File(at('dest/ok.txt')).readAsStringSync(), 'déjà là');
      expect(File(at('dest/ok (1).txt')).readAsStringSync(), 'ok');
      expect(File(at('evil.txt')).existsSync(), isFalse);
      expect(File('/abs.txt').existsSync(), isFalse);
    });

    test(
      'tar.gz is read; unsupported formats and bad files fail cleanly',
      () async {
        final tar = Archive()..addFile(ArchiveFile.bytes('t/x.txt', [120]));
        final gz = GZipEncoder().encode(TarEncoder().encode(tar));
        File(at('a.tar.gz')).writeAsBytesSync(gz);
        final r = await extractArchive(at('a.tar.gz'), at('dest'));
        expect(r.files, 1);
        expect(File(at('dest/t/x.txt')).existsSync(), isTrue);

        write('b.zip', 'not a zip');
        await expectLater(
          extractArchive(at('b.zip'), at('d2')),
          throwsA(anything),
        );
        await expectLater(
          extractArchive(at('c.rar'), at('d3')),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });

  group('categories', () {
    final now = DateTime(2030, 6, 15);

    test(
      'lists files of a kind, newest first, skipping hidden and Android',
      () async {
        write('Pictures/a.jpg', 'x', modified: DateTime(2030, 6, 1));
        write('DCIM/Camera/b.PNG', 'x', modified: DateTime(2030, 6, 10));
        write('Download/c.pdf', 'x');
        write('.cache/d.jpg', 'x');
        write('Android/data/e.jpg', 'x');
        write('Pictures/.hidden.jpg', 'x');
        final scan = await scanCategory(
          [tmp.path],
          FileCategory.images,
          now: now,
        );
        expect(scan.entries.map((e) => e.name), ['b.PNG', 'a.jpg']);
        expect(scan.complete, isTrue);
      },
    );

    test('recent: only files from the last days, any kind', () async {
      write('a.txt', 'x', modified: DateTime(2030, 6, 14));
      write('b.mp3', 'x', modified: DateTime(2030, 6, 1));
      write('c.zip', 'x', modified: DateTime(2030, 6, 13));
      final scan = await scanCategory(
        [tmp.path],
        FileCategory.recent,
        now: now,
      );
      expect(scan.entries.map((e) => e.name), ['a.txt', 'c.zip']);
    });

    test('a limit marks the result as partial', () async {
      for (var i = 0; i < 5; i++) {
        write('a$i.jpg', 'x', modified: DateTime(2030, 6, 1 + i));
      }
      final scan = await scanCategory(
        [tmp.path],
        FileCategory.images,
        limit: 3,
        now: now,
      );
      expect(scan.entries, hasLength(3));
      expect(scan.entries.first.name, 'a4.jpg');
      expect(scan.complete, isFalse);
    });

    test(
      'several roots are merged; archives and apks are told apart',
      () async {
        write('sd/x.zip', 'x');
        write('internal/y.tar.gz', 'x');
        write('internal/z.apk', 'x');
        final roots = [at('internal'), at('sd')];
        expect(
          (await scanCategory(
            roots,
            FileCategory.archives,
          )).entries.map((e) => e.name).toSet(),
          {'x.zip', 'y.tar.gz'},
        );
        expect(
          (await scanCategory(roots, FileCategory.apks)).entries.single.name,
          'z.apk',
        );
      },
    );
  });

  test(
    'removable volumes are the folders of /storage other than emulated',
    () async {
      Directory(at('storage/emulated/0')).createSync(recursive: true);
      Directory(at('storage/self')).createSync();
      Directory(at('storage/1A2B-3C4D')).createSync(recursive: true);
      File(at('storage/1A2B-3C4D/photo.jpg')).writeAsStringSync('x');
      File(at('storage/readme.txt')).writeAsStringSync('x');
      final volumes = await removableVolumes(storage: at('storage'));
      expect(volumes.map((v) => v.path), [at('storage/1A2B-3C4D')]);
      expect(volumes.single.label, 'Carte SD (1A2B-3C4D)');
      expect(await removableVolumes(storage: at('nothing')), isEmpty);
    },
  );

  test('kinds from extensions still match what categories rely on', () {
    expect(kindOfPath('/a/b.tgz'), FileKind.other); // not a listed extension
    expect(kindOfPath('/a/b.zip'), FileKind.archive);
    expect(kindOfPath('/a/b.APK'), FileKind.apk);
  });
}
