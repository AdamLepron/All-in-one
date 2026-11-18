import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/backup/backup_service.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late NotesStore notes;
  late OrganizerStore organizer;
  late AppSettings settings;
  late BackupService service;
  String at(String rel) => '${tmp.path}/$rel';

  Future<void> build({required String tag}) async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    for (final f in ['notes.db', 'organizer_bk_$tag.db']) {
      await databaseFactory.deleteDatabase('${await getDatabasesPath()}/$f');
    }
    notes = await NotesStore.open();
    organizer = await OrganizerStore.load(file: 'organizer_bk_$tag.db');
    service = BackupService(
      notes: notes,
      organizer: organizer,
      settings: settings,
      scansDir: at('data/scans'),
      recordingsDir: at('data/recordings'),
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => tmp = Directory.systemTemp.createTempSync('backup_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void file(String rel, String content) {
    final f = File(at(rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  Future<void> fill() async {
    await notes.save(
      Note(
        title: 'Courses',
        body: 'pain, lait\naccents : é è œ €',
        color: 3,
        pinned: true,
      ),
    );
    await notes.save(Note(title: 'Idée', body: 'application tout-en-un'));
    await organizer.saveTask(
      Task(
        title: 'Appeler Paul',
        due: DateTime(2026, 12, 1, 9),
        hasTime: true,
        priority: 3,
        list: 'Perso',
        repeat: Repeat.weekly,
      ),
    );
    await organizer.saveTask(
      Task(title: 'Fait', done: true, doneAt: DateTime(2026, 11, 1)),
    );
    await organizer.saveEvent(
      Event(
        title: 'Dentiste',
        start: DateTime(2026, 12, 5, 14),
        end: DateTime(2026, 12, 5, 15),
        location: 'Rue Pasteur',
        color: 2,
        reminder: 30,
        repeat: Repeat.yearly,
      ),
    );
    settings.themeMode = ThemeMode.dark;
    settings.accentIndex = 3;
    settings.setList('worldCities', ['Asia/Tokyo']);
    settings.galleryColumns = 5;
    file(
      'data/scans/1/scan.json',
      '{"title":"Facture","date":1,"pages":1,"text":"eau"}',
    );
    file('data/scans/1/page-1.jpg', 'jpeg');
    file('data/recordings/Mémo.m4a', 'audio');
  }

  test('a backup restores every kind of data after a wipe', () async {
    await build(tag: 'a');
    await fill();
    final path = await service.create(
      outputDir: at('out'),
      now: DateTime(2026, 11, 18, 9, 5, 7),
    );
    expect(path, endsWith('All-in-One-sauvegarde-20261118-090507.zip'));
    expect(File('$path.part').existsSync(), false); // no temporary file left
    expect(Directory(at('out')).listSync().length, 1);

    final info = await service.inspect(path);
    expect((info.notes, info.tasks, info.events, info.files), (2, 2, 1, 3));
    expect(info.created, DateTime(2026, 11, 18, 9, 5, 7));

    // Wipe everything, then restore.
    await notes.replaceAll([]);
    await organizer.replaceAll(taskRows: [], eventRows: []);
    await settings.replacePrefs({});
    Directory(at('data')).deleteSync(recursive: true);
    expect(notes.notes, isEmpty);
    expect(settings.accentIndex, 0);

    await service.restore(path);

    expect(notes.notes.map((n) => n.title).toSet(), {'Courses', 'Idée'});
    final courses = notes.notes.firstWhere((n) => n.title == 'Courses');
    expect(
      (courses.body, courses.color, courses.pinned),
      ('pain, lait\naccents : é è œ €', 3, true),
    );

    final task = organizer.tasks.firstWhere((t) => t.title == 'Appeler Paul');
    expect(
      (task.due, task.hasTime, task.priority, task.list, task.repeat),
      (DateTime(2026, 12, 1, 9), true, 3, 'Perso', Repeat.weekly),
    );
    expect(organizer.tasks.firstWhere((t) => t.title == 'Fait').done, true);
    final event = organizer.events.single;
    expect(
      (event.title, event.location, event.reminder, event.repeat),
      ('Dentiste', 'Rue Pasteur', 30, Repeat.yearly),
    );

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.accentIndex, 3);
    expect(settings.galleryColumns, 5);
    expect(settings.list('worldCities'), ['Asia/Tokyo']);

    expect(
      File(at('data/scans/1/scan.json')).readAsStringSync(),
      contains('Facture'),
    );
    expect(File(at('data/scans/1/page-1.jpg')).existsSync(), true);
    expect(File(at('data/recordings/Mémo.m4a')).readAsStringSync(), 'audio');
  });

  test('restoring replaces what is there now, not merges', () async {
    await build(tag: 'b');
    await notes.save(Note(title: 'Ancienne', body: 'x'));
    final path = await service.create(
      outputDir: at('out'),
      includeFiles: false,
    );
    await notes.save(Note(title: 'Écrite après', body: 'y'));
    expect(notes.notes.length, 2);
    await service.restore(path);
    expect(notes.notes.single.title, 'Ancienne');
  });

  test('a backup without files leaves scans and recordings alone', () async {
    await build(tag: 'c');
    file('data/scans/1/scan.json', 'avant');
    final path = await service.create(
      outputDir: at('out'),
      includeFiles: false,
    );
    expect((await service.inspect(path)).files, 0);
    file('data/scans/2/scan.json', 'ajouté après');
    await service.restore(path);
    expect(File(at('data/scans/2/scan.json')).existsSync(), true);
  });

  test('bad files are rejected and change nothing', () async {
    await build(tag: 'd');
    await notes.save(Note(title: 'À garder', body: 'z'));

    File(at('pas-un-zip.zip')).writeAsStringSync('texte');
    await expectLater(
      service.restore(at('pas-un-zip.zip')),
      throwsA(isA<BackupException>()),
    );

    // A zip without data.json.
    final other = ZipFileEncoder()..create(at('autre.zip'));
    file('autre.txt', 'x');
    await other.addFile(File(at('autre.txt')));
    await other.close();
    await expectLater(
      service.restore(at('autre.zip')),
      throwsA(isA<BackupException>()),
    );

    // A backup from a newer format.
    file(
      'futur/data.json',
      '{"format": 99, "notes": [], "tasks": [], "events": [], "preferences": {}}',
    );
    final future = ZipFileEncoder()..create(at('futur.zip'));
    await future.addFile(File(at('futur/data.json')), 'data.json');
    await future.close();
    await expectLater(
      service.restore(at('futur.zip')),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('plus récente'),
        ),
      ),
    );

    // A damaged backup: rows that cannot be read stop the restore before deletion.
    file(
      'abime/data.json',
      '{"format": 1, "notes": [{"id": 1}], "tasks": [], "events": [], "preferences": {}}',
    );
    final broken = ZipFileEncoder()..create(at('abime.zip'));
    await broken.addFile(File(at('abime/data.json')), 'data.json');
    await broken.close();
    await expectLater(service.restore(at('abime.zip')), throwsA(anything));

    expect(notes.notes.single.title, 'À garder'); // untouched by every failure
  });

  test('the same data can be backed up twice without clashing', () async {
    await build(tag: 'e');
    await fill();
    final a = await service.create(
      outputDir: at('out'),
      now: DateTime(2026, 11, 18, 9),
    );
    final b = await service.create(
      outputDir: at('out'),
      now: DateTime(2026, 11, 18, 9, 0, 1),
    );
    expect(a, isNot(b));
    expect(Directory(at('out')).listSync().length, 2);
  });
}
