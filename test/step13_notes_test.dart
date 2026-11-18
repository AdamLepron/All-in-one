import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/backup/backup_service.dart';
import 'package:all_in_one/modules/notes/note_files.dart';
import 'package:all_in_one/modules/notes/notes_page.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late NotesStore store;
  var counter = 0;

  Future<NotesStore> openFresh([String? name]) async {
    final file = name ?? 'notes13_${counter++}.db';
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/$file');
    return NotesStore.open(file: file);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('step13');
    NoteFiles.locate = () async => '${tmp.path}/note_files';
    store = await openFresh();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a database made before 1.3 is upgraded without losing notes', () async {
    const file = 'notes13_old.db';
    final path = '${await getDatabasesPath()}/$file';
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, body TEXT NOT NULL, color INTEGER NOT NULL, '
          'pinned INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
        ),
      ),
    );
    await old.insert('notes', {
      'title': 'Ancienne',
      'body': 'texte',
      'color': 2,
      'pinned': 1,
      'updated_at': 1000,
    });
    await old.close();

    final upgraded = await NotesStore.open(file: file);
    final n = upgraded.notes.single;
    expect(
      (n.title, n.body, n.color, n.pinned),
      ('Ancienne', 'texte', 2, true),
    );
    expect(n.folder, '');
    expect(n.attachments, isEmpty);
    expect(n.inTrash, isFalse);
  });

  test('notes from an old backup (no new fields) still load', () {
    final n = Note.fromMap({
      'id': 1,
      'title': 'a',
      'body': 'b',
      'color': 0,
      'pinned': 0,
      'updated_at': 5,
    });
    expect(n.folder, '');
    expect(n.attachments, isEmpty);
    expect(n.trashedAt, isNull);
  });

  test(
    'trash: hidden from lists and search, recoverable, purged after 30 days',
    () async {
      final a = Note(title: 'Garder', body: 'x');
      final b = Note(title: 'Jeter', body: 'x', pinned: true);
      await store.save(a);
      await store.save(b);
      await store.moveToTrash(b);
      expect(store.notes.map((n) => n.title), ['Garder']);
      expect(store.search('jeter'), isEmpty);
      expect(store.trash.single.title, 'Jeter');
      expect(store.trash.single.pinned, isFalse); // unpinned when trashed

      await store.recover(b);
      expect(store.notes, hasLength(2));
      expect(store.trash, isEmpty);

      await store.moveToTrash(b);
      // Not old enough yet.
      await store.purgeTrash(now: DateTime.now().add(const Duration(days: 29)));
      expect(store.trash, hasLength(1));
      b.attachments.add('photo.jpg');
      await store.save(b, touch: false);
      final gone = await store.purgeTrash(
        now: DateTime.now().add(const Duration(days: 31)),
      );
      expect(store.trash, isEmpty);
      expect(gone, ['photo.jpg']); // so the files can be deleted too
      expect(store.notes.single.title, 'Garder');
    },
  );

  test('empty the trash returns the attachments to delete', () async {
    final a = Note(title: 'A', attachments: ['x.pdf']);
    await store.save(a);
    await store.moveToTrash(a);
    expect(await store.emptyTrash(), ['x.pdf']);
    expect(store.trash, isEmpty);
    expect(await store.emptyTrash(), isEmpty);
  });

  test('a note holding only an attachment is not discarded as empty', () async {
    final a = Note(attachments: ['x.pdf']);
    await store.save(a);
    expect(store.notes, hasLength(1));
    final blank = Note();
    await store.save(blank);
    expect(store.notes, hasLength(1));
  });

  test('folders: listed, renamed, deleted keeping the notes', () async {
    await store.save(Note(title: 'a', folder: 'Travail'));
    await store.save(Note(title: 'b', folder: 'travail ideas'));
    await store.save(Note(title: 'c'));
    expect(
      store.folders,
      ['travail ideas', 'Travail']
        ..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase())),
    );
    await store.renameFolder('Travail', 'Boulot');
    expect(store.notes.where((n) => n.folder == 'Boulot'), hasLength(1));
    await store.renameFolder('Boulot', '  '); // ignored
    expect(store.folders, contains('Boulot'));
    await store.deleteFolder('Boulot');
    expect(store.folders, ['travail ideas']);
    expect(store.notes, hasLength(3));
  });

  test('ticking a checklist line only changes that line', () async {
    final n = Note(
      title: 'Courses',
      body: '# Liste\n- [ ] Lait\n- [x] Pain\n  - [ ] Beurre\ntexte [ ] libre',
    );
    await store.save(n);
    await store.toggleCheck(n, 1);
    await store.toggleCheck(n, 2);
    await store.toggleCheck(n, 3);
    await store.toggleCheck(n, 0); // not a checkbox
    await store.toggleCheck(n, 4); // not at line start
    await store.toggleCheck(n, 99); // out of range
    expect(
      store.notes.single.body,
      '# Liste\n- [x] Lait\n- [ ] Pain\n  - [x] Beurre\ntexte [ ] libre',
    );
  });

  test('plainLine strips Markdown markers', () {
    expect(plainLine('## Titre **gras**'), 'Titre gras');
    expect(plainLine('- puce `code`'), '• puce code');
    expect(plainLine('> citation ~~barrée~~'), 'citation barrée');
    expect(plainLine('[lien](https://x.y) fin'), 'lien fin');
  });

  test('attachments are copied, never overwritten, and removable', () async {
    final src = File('${tmp.path}/in/rapport.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('un');
    final first = await NoteFiles.add(src.path);
    src.writeAsStringSync('deux');
    final second = await NoteFiles.add(src.path);
    expect(first, 'rapport.pdf');
    expect(second, 'rapport (1).pdf');
    expect(await (await NoteFiles.file(first)).readAsString(), 'un');
    expect(NoteFiles.isImage('a.JPG'), isTrue);
    expect(NoteFiles.isImage('a.pdf'), isFalse);
    // A name can never point outside the directory.
    expect(
      (await NoteFiles.file('../../etc/passwd')).path,
      '${tmp.path}/note_files/passwd',
    );
    await NoteFiles.remove([first, 'absent.txt']);
    expect(await (await NoteFiles.file(first)).exists(), isFalse);
    expect(await (await NoteFiles.file(second)).exists(), isTrue);
  });

  test('a backup carries folders, the trash and the attachments', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final organizer = await OrganizerStore.load(file: 'organizer13.db');
    final filesDir = '${tmp.path}/note_files';
    File('$filesDir/a.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('pièce');
    await store.save(
      Note(title: 'Vive', folder: 'Perso', attachments: ['a.txt']),
    );
    final dead = Note(title: 'Morte');
    await store.save(dead);
    await store.moveToTrash(dead);

    final service = BackupService(
      notes: store,
      organizer: organizer,
      settings: settings,
      scansDir: '${tmp.path}/scans',
      recordingsDir: '${tmp.path}/rec',
      noteFilesDir: filesDir,
    );
    final zip = await service.create(outputDir: '${tmp.path}/out');

    await store.replaceAll(const []);
    File('$filesDir/a.txt').deleteSync();
    expect(store.notes, isEmpty);

    await service.restore(zip);
    expect(store.notes.single.folder, 'Perso');
    expect(store.notes.single.attachments, ['a.txt']);
    expect(store.trash.single.title, 'Morte');
    expect(File('$filesDir/a.txt').readAsStringSync(), 'pièce');
  });

  testWidgets('notes page: folders, checklist ticking, trash and restore', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    // Real I/O (sqlite) does not run inside the fake clock.
    await tester.runAsync(() async {
      await store.save(
        Note(
          title: 'Courses',
          body: '- [ ] Lait\n- [x] Pain',
          folder: 'Maison',
        ),
      );
      await store.save(Note(title: 'Idée', body: 'blabla'));
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
        ],
        child: const MaterialApp(home: NotesPage()),
      ),
    );
    await tester.pump();
    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Idée'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Maison'));
    await tester.pump();
    expect(find.text('Idée'), findsNothing);

    // Tick "Lait" straight from the list.
    await tester.runAsync(() async {
      await tester.tap(find.text('Lait'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(
      store.notes.firstWhere((n) => n.title == 'Courses').body,
      '- [x] Lait\n- [x] Pain',
    );

    // Trash the note through its menu, then bring it back.
    await tester.longPress(find.text('Courses'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Supprimer'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.trash.single.title, 'Courses');
    expect(find.text('Note placée dans la corbeille'), findsOneWidget);

    await tester.tap(find.textContaining('Corbeille'));
    await tester.pumpAndSettle();
    expect(find.text('Courses'), findsOneWidget);
    await tester.tap(find.text('Courses'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Restaurer'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.trash, isEmpty);
    expect(store.notes, hasLength(2));
  });
}
