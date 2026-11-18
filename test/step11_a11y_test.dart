import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/main.dart' show AllInOneApp;
import 'package:all_in_one/modules/calculator/calculator_page.dart';
import 'package:all_in_one/modules/calendar/calendar_page.dart';
import 'package:all_in_one/modules/calendar/event_editor_page.dart';
import 'package:all_in_one/modules/notes/note_editor_page.dart';
import 'package:all_in_one/modules/clock/clock_controller.dart';
import 'package:all_in_one/modules/clock/clock_page.dart';
import 'package:all_in_one/modules/converter/converter_page.dart';
import 'package:all_in_one/modules/equalizer/equalizer_controller.dart';
import 'package:all_in_one/modules/equalizer/equalizer_page.dart';
import 'package:all_in_one/modules/files/files_ui.dart';
import 'package:all_in_one/modules/gallery/gallery_page.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/music/music_page.dart';
import 'package:all_in_one/modules/music/song.dart';
import 'package:all_in_one/modules/notes/notes_page.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/recorder/recorder_controller.dart';
import 'package:all_in_one/modules/recorder/recorder_page.dart';
import 'package:all_in_one/modules/scanner/scan_store.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:all_in_one/modules/tasks/tasks_page.dart';
import 'package:all_in_one/modules/transfer/transfer_page.dart';
import 'package:all_in_one/shell/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late NotesStore notes;
  late OrganizerStore organizer;
  late AppSettings settings;
  late MusicController music;
  late MediaLibrary library;
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> prepare(WidgetTester tester) async {
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('a11y');
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/notes.db',
      );
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/organizer_a11y.db',
      );
      notes = await NotesStore.open();
      organizer = await OrganizerStore.load(file: 'organizer_a11y.db');
      await notes.save(
        Note(title: 'Courses', body: 'pain, lait', color: 3, pinned: true),
      );
      await notes.save(Note(title: 'Idées', body: 'application'));
      final today = DateTime.now();
      await organizer.saveTask(
        Task(
          title: 'Appeler Paul',
          due: DateTime(today.year, today.month, today.day),
          priority: 3,
        ),
      );
      await organizer.saveEvent(
        Event(
          title: 'Réunion',
          start: DateTime(today.year, today.month, today.day, 14),
          end: DateTime(today.year, today.month, today.day, 15),
        ),
      );
    });
    music = MusicController(settings)
      ..debugSetLibrary([
        for (var i = 0; i < 6; i++)
          Song(
            id: i,
            title: 'Titre $i',
            artist: 'Artiste',
            album: 'Album',
            albumId: 1,
            duration: const Duration(seconds: 200),
            uri: 'content://$i',
          ),
      ], playingIndex: 1);
    library = MediaLibrary()
      ..debugSet([
        for (var i = 0; i < 12; i++)
          Media(
            id: i,
            video: i % 5 == 0,
            path: '/p/$i',
            name: 'IMG_$i',
            date: DateTime.now().subtract(Duration(hours: i)),
            uri: 'c://$i',
            album: 'Appareil photo',
            duration: const Duration(seconds: 20),
          ),
      ]);
  }

  Widget harness(Widget child, {double textScale = 1}) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: notes),
      ChangeNotifierProvider.value(value: organizer),
      ChangeNotifierProvider.value(value: music),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider(
        create: (_) => EqualizerController(settings, music),
      ),
      ChangeNotifierProvider(create: (_) => FilesClipboard()),
      ChangeNotifierProvider(create: (_) => ClockController()),
      ChangeNotifierProvider(
        create: (_) =>
            RecorderController(directory: () async => '${tmp.path}/rec'),
      ),
      ChangeNotifierProvider(
        create: (_) => ScanStore(directory: () async => '${tmp.path}/scans'),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
      darkTheme: buildTheme(const Color(0xFF5B5BD6), Brightness.dark),
      home: child,
    ),
  );

  final screens = <String, Widget Function()>{
    'Accueil et onglets': () => const AllInOneApp(),
    'Notes': () => const NotesPage(),
    'Tâches': () => const TasksPage(),
    'Agenda': () => const CalendarPage(),
    'Nouvel événement': () => EventEditorPage(day: DateTime(2030, 3, 4)),
    'Éditeur de note': () => const NoteEditorPage(),
    'Calculatrice': () => const CalculatorPage(),
    'Convertisseur': () => const ConverterPage(),
    'Horloge': () => const ClockPage(),
    'Musique': () => const MusicPage(),
    'Égaliseur': () => const EqualizerPage(),
    'Galerie': () => const GalleryPage(),
    'Réglages': () => const SettingsPage(),
    'Transfert': () => const TransferPage(),
    'Enregistreur': () => const RecorderPage(),
  };

  Widget harnessApp(double textScale) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: notes),
      ChangeNotifierProvider.value(value: organizer),
      ChangeNotifierProvider.value(value: music),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider(
        create: (_) => EqualizerController(settings, music),
      ),
      ChangeNotifierProvider(create: (_) => FilesClipboard()),
      ChangeNotifierProvider(create: (_) => ClockController()),
      ChangeNotifierProvider(
        create: (_) =>
            RecorderController(directory: () async => '${tmp.path}/rec'),
      ),
      ChangeNotifierProvider(
        create: (_) => ScanStore(directory: () async => '${tmp.path}/scans'),
      ),
    ],
    child: const AllInOneApp(),
  );

  Future<void> show(
    WidgetTester tester,
    Widget Function() build, {
    double textScale = 1,
    Size size = const Size(412, 892),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // The real app wraps itself in its own providers; the others are given them.
    final widget = build();
    await tester.pumpWidget(
      widget is AllInOneApp
          ? harnessApp(textScale)
          : harness(widget, textScale: textScale),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('main screens meet the accessibility guidelines', (tester) async {
    await prepare(tester);
    final handle = tester.ensureSemantics();
    final issues = <String>[];
    for (final entry in screens.entries) {
      await show(tester, entry.value);
      for (final (name, guideline) in [
        ('cible tactile', androidTapTargetGuideline),
        ('libellé', labeledTapTargetGuideline),
        ('contraste', textContrastGuideline),
      ]) {
        final result = await guideline.evaluate(tester);
        if (!result.passed) {
          issues.add(
            '${entry.key} · $name : ${(result.reason ?? '').split('\n').take(3).join(' | ')}',
          );
        }
      }
    }
    handle.dispose();
    expect(issues, isEmpty, reason: issues.join('\n'));
  });

  testWidgets('nothing overflows with the system text at 150 % and 200 %', (
    tester,
  ) async {
    await prepare(tester);
    final problems = <String>[];
    for (final scale in [1.5, 2.0]) {
      for (final entry in screens.entries) {
        await show(tester, entry.value, textScale: scale);
        final error = tester.takeException();
        if (error != null) {
          problems.add(
            '${entry.key} à ${(scale * 100).round()} % : ${error.toString().split('\n').first}',
          );
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
