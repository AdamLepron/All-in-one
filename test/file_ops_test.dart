import 'dart:io';

import 'package:all_in_one/core/util.dart';
import 'package:all_in_one/modules/files/file_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  String at(String rel) => p.join(tmp.path, rel);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('files_test');
    await Directory(at('docs/sub')).create(recursive: true);
    await File(at('docs/a.txt')).writeAsString('hello');
    await File(at('docs/sub/b.txt')).writeAsString('world!');
    await File(at('.hidden')).writeAsString('x');
    await File(at('photo.JPG')).writeAsString('img');
    await Directory(at('dest')).create();
  });
  tearDown(() => tmp.delete(recursive: true));

  test('listFolder sorts folders first and hides dot files', () async {
    final names = (await listFolder(tmp.path)).map((e) => e.name).toList();
    expect(names, ['dest', 'docs', 'photo.JPG']);
    final all = await listFolder(tmp.path, showHidden: true);
    expect(all.map((e) => e.name), contains('.hidden'));
    expect(all.firstWhere((e) => e.name == 'docs').size, 2);
    expect(all.firstWhere((e) => e.name == 'photo.JPG').kind, FileKind.image);
  });

  test('copy is recursive and never overwrites', () async {
    await copyEntity(at('docs'), at('dest'));
    expect(await File(at('dest/docs/sub/b.txt')).readAsString(), 'world!');
    final second = await copyEntity(at('docs'), at('dest'));
    expect(p.basename(second), 'docs (1)');
    final file = await copyEntity(at('docs/a.txt'), at('docs'));
    expect(p.basename(file), 'a (1).txt');
    expect(
      () => copyEntity(at('docs'), at('docs/sub')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('move, rename and size', () async {
    await moveEntity(at('docs/a.txt'), at('dest'));
    expect(File(at('docs/a.txt')).existsSync(), false);
    expect(File(at('dest/a.txt')).existsSync(), true);
    await renameEntity(at('dest/a.txt'), 'c.txt');
    expect(File(at('dest/c.txt')).existsSync(), true);
    expect(() => renameEntity(at('dest/c.txt'), 'c.txt'), returnsNormally);
    await File(at('dest/d.txt')).writeAsString('d');
    expect(
      () => renameEntity(at('dest/c.txt'), 'd.txt'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await sizeOf(at('docs')), 6);
    expect(
      () => moveEntity(at('docs'), at('docs/sub')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('trash keeps, restores and purges', () async {
    final trash = Trash(at('.trash'));
    final item = await trash.put(at('docs'));
    expect(Directory(at('docs')).existsSync(), false);
    expect((await trash.items()).single.name, 'docs');
    await Directory(at('docs')).create(); // the place gets taken meanwhile
    final restored = await trash.restore(item);
    expect(p.basename(restored), 'docs (1)');
    expect(File(p.join(restored, 'sub/b.txt')).existsSync(), true);
    expect(await trash.items(), isEmpty);

    await trash.put(at('photo.JPG'));
    await trash.purgeExpired();
    expect((await trash.items()).length, 1);
    await trash.empty();
    expect(await trash.items(), isEmpty);
    expect(File(at('photo.JPG')).existsSync(), false);
  });

  test('formatters', () {
    expect(formatBytes(0), '0 o');
    expect(formatBytes(1500), '1,5 ko');
    expect(formatBytes(64000000000), '64,0 Go');
    expect(formatDuration(const Duration(seconds: 187)), '3:07');
    expect(formatDuration(const Duration(seconds: 3765)), '1:02:45');
  });
}
