import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/main.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Loads the real Roboto and Material Icons fonts so screenshots are readable.
Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
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
  await (FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'))).load();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('main flows work end to end', (tester) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late AppSettings settings;
    late NotesStore notes;
    await tester.runAsync(() async {
      await loadFonts();
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
      await databaseFactory.deleteDatabase('${await getDatabasesPath()}/notes.db');
      notes = await NotesStore.open();
    });

    Future<void> settle() async {
      // Database calls hop between real I/O and the test's fake clock.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    Future<void> shot(String name) => expectLater(
        find.byType(AllInOneApp), matchesGoldenFile('screenshots/$name.png'));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: notes),
      ],
      child: const AllInOneApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Raccourcis'), findsOneWidget);
    await shot('01_home_empty');

    // Create a note through the UI.
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Courses');
    await tester.enterText(find.byType(TextField).last, 'Pain, lait, œufs');
    await tester.pump();
    await shot('02_note_editor');
    await tester.pageBack();
    await settle();
    expect(notes.notes.single.title, 'Courses');

    await tester.runAsync(() async {
      await notes.save(Note(title: 'Idées projet', body: 'Lecteur de musique avec mini-lecteur persistant, égaliseur par casque.', color: 5));
      await notes.save(Note(title: 'Réunion lundi', body: 'Préparer la démo\nEnvoyer le compte rendu', color: 3, pinned: true));
    });
    await tester.pumpAndSettle();
    expect(find.text('Reprendre'), findsOneWidget);
    await shot('03_home');

    // Notes module.
    await tester.tap(find.text('Tout voir'));
    await tester.pumpAndSettle();
    expect(find.text('Réunion lundi'), findsOneWidget);
    await shot('04_notes');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Tools tab and calculator.
    await tester.tap(find.text('Outils'));
    await tester.pumpAndSettle();
    await shot('05_tools');
    await tester.tap(find.text('Calculatrice').last);
    await tester.pumpAndSettle();
    for (final key in ['7', '×', '8']) {
      await tester.tap(find.text(key));
    }
    await tester.pump();
    expect(find.text('= 56'), findsOneWidget);
    await shot('06_calculator');
    await tester.tap(find.text('='));
    await tester.pump();
    expect(find.text('56'), findsOneWidget);
    expect(settings.calcHistory.first, '7×8 = 56');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Converter.
    await tester.tap(find.text('Convertisseur').last);
    await tester.pumpAndSettle();
    expect(find.text('0,001'), findsOneWidget); // 1 m in km
    await shot('07_converter');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Media tab (all coming soon) and search.
    await tester.tap(find.text('Médias'));
    await tester.pumpAndSettle();
    await shot('08_media');
    await tester.tap(find.text('Recherche'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'lecteur');
    await tester.pumpAndSettle();
    expect(find.text('Idées projet'), findsOneWidget);
    await shot('09_search');

    // Dark AMOLED theme.
    settings
      ..themeMode = ThemeMode.dark
      ..amoled = true
      ..accentIndex = 1;
    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();
    await shot('10_home_dark');
  });
}
