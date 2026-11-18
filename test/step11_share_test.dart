import 'dart:io';

import 'package:all_in_one/modules/share/incoming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IncomingFile f(String name, [String? mime]) =>
      IncomingFile('/cache/$name', name, mime);

  test('kinds come from the extension first, then the type', () {
    expect(f('facture.PDF').kind, IncomingKind.pdf);
    expect(f('x', 'application/pdf').kind, IncomingKind.pdf);
    expect(f('notes.md').kind, IncomingKind.text);
    expect(f('lisez-moi', 'text/plain').kind, IncomingKind.text);
    expect(f('photo.jpg').kind, IncomingKind.image);
    expect(f('photo', 'image/webp').kind, IncomingKind.image);
    expect(f('clip.mp4').kind, IncomingKind.video);
    expect(f('son.m4a').kind, IncomingKind.audio);
    expect(f('rapport.docx').kind, IncomingKind.document);
    // A wrong type from the sender does not override a clear extension.
    expect(f('photo.png', 'application/octet-stream').kind, IncomingKind.image);
    expect(f('archive.zip', 'application/zip').kind, IncomingKind.other);
  });

  test('content from the platform is read, or rejected when empty', () {
    final shared = Incoming.fromMap({
      'action': 'send',
      'text': null,
      'files': [
        {'path': '/c/a.jpg', 'name': 'a.jpg', 'mime': 'image/jpeg'},
        {'path': '/c/b', 'name': null, 'mime': null},
        {'name': 'sans chemin'},
      ],
    })!;
    expect(shared.files.length, 2);
    expect(shared.files.last.name, 'b'); // falls back to the file name
    expect(shared.view, false);

    final link = Incoming.fromMap({
      'action': 'send',
      'text': 'https://exemple.fr',
      'files': [],
    })!;
    expect(link.isText, true);
    expect(
      Incoming.fromMap({'action': 'send', 'text': '   ', 'files': []}),
      isNull,
    );
    expect(Incoming.fromMap({'action': 'view'}), isNull);
    expect(
      Incoming.fromMap({
        'action': 'view',
        'files': [
          {'path': '/c/a.pdf', 'name': 'a.pdf'},
        ],
      })!.view,
      true,
    );
  });

  test('actions depend on what was received', () {
    expect(actionsFor(const Incoming(text: 'Un lien')), [
      ShareAction.newNote,
      ShareAction.newTask,
      ShareAction.newDocument,
      ShareAction.copyText,
    ]);
    expect(
      actionsFor(Incoming(files: [f('a.jpg')])),
      contains(ShareAction.editPhoto),
    );
    expect(
      actionsFor(Incoming(files: [f('a.mp4')])),
      contains(ShareAction.editVideo),
    );
    expect(
      actionsFor(Incoming(files: [f('a.mp3')])).first,
      ShareAction.playAudio,
    );
    expect(
      actionsFor(Incoming(files: [f('a.md')])),
      contains(ShareAction.editDocument),
    );
    expect(
      actionsFor(Incoming(files: [f('a.pdf')])),
      isNot(contains(ShareAction.editDocument)),
    );
    expect(
      actionsFor(Incoming(files: [f('a.zip')])).first,
      ShareAction.saveDownloads,
    );
    // Several files: save them together, to Images only if all are pictures.
    expect(
      actionsFor(Incoming(files: [f('a.jpg'), f('b.jpg')])),
      contains(ShareAction.saveGallery),
    );
    expect(
      actionsFor(Incoming(files: [f('a.jpg'), f('b.pdf')])),
      isNot(contains(ShareAction.saveGallery)),
    );
    // Every file set can be sent on to another device.
    for (final name in [
      'a.jpg',
      'a.mp4',
      'a.mp3',
      'a.pdf',
      'a.md',
      'a.docx',
      'a.zip',
    ]) {
      expect(
        actionsFor(Incoming(files: [f(name)])),
        contains(ShareAction.sendWifi),
        reason: name,
      );
    }
  });

  test('"Open with" acts at once when the target is obvious', () {
    Incoming view(String name) => Incoming(files: [f(name)], view: true);
    expect(directAction(view('a.pdf')), ShareAction.open);
    expect(directAction(view('a.mp4')), ShareAction.playVideo);
    expect(directAction(view('a.mp3')), ShareAction.playAudio);
    expect(directAction(view('a.zip')), isNull);
    // Sharing always asks; several files always ask.
    expect(directAction(Incoming(files: [f('a.pdf')])), isNull);
    expect(
      directAction(Incoming(files: [f('a.pdf'), f('b.pdf')], view: true)),
      isNull,
    );
  });

  test('saving copies files without overwriting', () async {
    final tmp = Directory.systemTemp.createTempSync('share_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/a.txt').writeAsStringSync('un');
    final file = IncomingFile('${tmp.path}/a.txt', 'a.txt', 'text/plain');
    final dir = '${tmp.path}/dest';
    final first = await saveIncomingFiles([file], dir);
    final second = await saveIncomingFiles([file, file], dir);
    expect(first.single, '$dir/a.txt');
    expect(second, ['$dir/a (1).txt', '$dir/a (2).txt']);
    expect(File(second.last).readAsStringSync(), 'un');
    expect(file.size, 2);
  });

  test('titles from shared text', () {
    expect(titleOfText('  Premier titre\nsuite'), 'Premier titre');
    expect(titleOfText('x' * 300).length, 101);
    expect(titleOfText(''), '');
  });
}
