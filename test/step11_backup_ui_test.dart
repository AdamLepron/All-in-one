import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/backup/backup_page.dart';
import 'package:all_in_one/modules/notes/note_files.dart';
import 'package:all_in_one/modules/reader/annotations.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/recorder/recorder_controller.dart';
import 'package:all_in_one/modules/scanner/scan_store.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  if (!Directory(dir).existsSync()) return;
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(read('Roboto-$f.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

void main() {
  testWidgets('creating then restoring a backup from the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late Directory tmp;
    late NotesStore notes;
    late OrganizerStore organizer;
    late AppSettings settings;
    await tester.runAsync(() async {
      await loadFonts();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmp = Directory.systemTemp.createTempSync('backup_ui');
      NoteFiles.locate = () async => '${tmp.path}/note_files';
      AnnotationStore.locate = () async => '${tmp.path}/pdf_annotations';
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/notes.db',
      );
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/organizer_bkui.db',
      );
      notes = await NotesStore.open();
      organizer = await OrganizerStore.load(file: 'organizer_bkui.db');
      await notes.save(Note(title: 'Courses', body: 'pain'));
      await notes.save(Note(title: 'Idée', body: 'tout-en-un'));
      await organizer.saveTask(Task(title: 'Appeler Paul'));
    });
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = '${tmp.path}/Sauvegardes';

    /// Real file and database work runs outside the fake clock, so wait
    /// in real time until the progress bar is gone.
    Future<void> settle() async {
      var quiet = 0;
      for (var i = 0; i < 400 && quiet < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        quiet = find.byType(LinearProgressIndicator).evaluate().isEmpty
            ? quiet + 1
            : 0;
      }
      await tester.pumpAndSettle();
    }

    Future<void> shot(String name) async {
      if (!autoUpdateGoldenFiles) return;
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screenshots/$name.png'),
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: notes),
          ChangeNotifierProvider.value(value: organizer),
          ChangeNotifierProvider(
            create: (_) =>
                ScanStore(directory: () async => '${tmp.path}/scans'),
          ),
          ChangeNotifierProvider(
            create: (_) => RecorderController(
              directory: () async => '${tmp.path}/recordings',
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
          home: BackupPage(directory: out),
        ),
      ),
    );
    await settle();
    expect(find.textContaining('Aucune sauvegarde'), findsOneWidget);
    await shot('62_backup');

    await tester.tap(find.text('Créer une sauvegarde'));
    await settle();
    final created = Directory(out)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'))
        .toList();
    expect(created.length, 1);
    expect(find.textContaining('All-in-One-sauvegarde-'), findsWidgets);
    expect(find.textContaining('Aucune sauvegarde'), findsNothing);

    // Change the data, then restore the backup from the list.
    await tester.runAsync(() async {
      await notes.save(Note(title: 'Après la sauvegarde', body: 'à perdre'));
      await organizer.saveTask(Task(title: 'Tâche ajoutée après'));
    });
    expect(notes.notes.length, 3);

    await tester.tap(find.textContaining('All-in-One-sauvegarde-').first);
    await settle(); // reading the backup is real file work
    expect(find.text('Restaurer cette sauvegarde ?'), findsOneWidget);
    expect(
      find.textContaining('2 notes, 1 tâche, 0 événement'),
      findsOneWidget,
    );
    await shot('63_backup_restore');
    await tester.tap(find.text('Remplacer et restaurer'));
    await settle();

    expect(notes.notes.map((n) => n.title).toSet(), {'Courses', 'Idée'});
    expect(organizer.tasks.single.title, 'Appeler Paul');
    expect(find.textContaining('Restauration terminée'), findsOneWidget);

    // A file that is not a backup is refused with a clear message.
    final fake = File('${tmp.path}/autre.zip')
      ..writeAsStringSync('pas une sauvegarde');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: notes),
          ChangeNotifierProvider.value(value: organizer),
          ChangeNotifierProvider(
            create: (_) =>
                ScanStore(directory: () async => '${tmp.path}/scans'),
          ),
          ChangeNotifierProvider(
            create: (_) => RecorderController(
              directory: () async => '${tmp.path}/recordings',
            ),
          ),
        ],
        child: MaterialApp(
          home: BackupPage(directory: out, pickFile: () async => fake.path),
        ),
      ),
    );
    await settle();
    await tester.tap(find.text('Restaurer…'));
    await settle();
    expect(
      find.textContaining("pas une sauvegarde All-in-One"),
      findsOneWidget,
    );
    expect(find.text('Restaurer cette sauvegarde ?'), findsNothing);
  });
}
