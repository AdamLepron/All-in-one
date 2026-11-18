import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/share/incoming.dart';
import 'package:all_in_one/modules/share/share_sheet.dart';
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
  late NotesStore notes;
  late OrganizerStore organizer;

  Future<void> start(WidgetTester tester, Incoming incoming) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await loadFonts();
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/notes.db',
      );
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/organizer_share.db',
      );
      notes = await NotesStore.open();
      organizer = await OrganizerStore.load(file: 'organizer_share.db');
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: notes),
          ChangeNotifierProvider.value(value: organizer),
          ChangeNotifierProvider(create: (_) => MusicController(settings)),
          ChangeNotifierProvider(create: (_) => MediaLibrary()),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => handleIncoming(context, incoming),
                  child: const Text('Recevoir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Recevoir'));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('shared text becomes a note or a task', (tester) async {
    await start(
      tester,
      const Incoming(
        text: 'À lire : https://exemple.fr/article\nSuite du message',
      ),
    );
    expect(find.text("Reçu d'une autre application"), findsOneWidget);
    expect(find.textContaining('https://exemple.fr/article'), findsOneWidget);
    expect(find.text('Nouvelle note'), findsOneWidget);
    expect(find.text('Nouvelle tâche'), findsOneWidget);
    await shot(tester, '60_share_text');

    await tester.tap(find.text('Nouvelle note'));
    await settle(tester);
    expect(
      notes.notes.single.body,
      startsWith('À lire : https://exemple.fr/article'),
    );
    // The note opens in its editor, with the shared text.
    expect(find.textContaining('Suite du message'), findsWidgets);
  });

  testWidgets('shared text can start a task, pre-filled and not yet saved', (
    tester,
  ) async {
    await start(
      tester,
      const Incoming(text: 'Appeler le plombier\nvoir devis'),
    );
    await tester.tap(find.text('Nouvelle tâche'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Appeler le plombier'),
      findsOneWidget,
    );
    // Nothing exists until the user saves it, and there is nothing to delete.
    expect(organizer.tasks, isEmpty);
    expect(find.text('Supprimer'), findsNothing);
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    expect(organizer.tasks.single.title, 'Appeler le plombier');
  });

  testWidgets('a shared PDF offers the right actions', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('share_ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/contrat.pdf').writeAsBytesSync(List.filled(184000, 1));
    await start(
      tester,
      Incoming(
        files: [
          IncomingFile(
            '${tmp.path}/contrat.pdf',
            'contrat.pdf',
            'application/pdf',
          ),
        ],
      ),
    );
    expect(find.textContaining('contrat.pdf · 184 ko'), findsOneWidget);
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(find.text('Enregistrer dans Documents'), findsOneWidget);
    expect(find.text('Envoyer à un autre appareil par Wi-Fi'), findsOneWidget);
    expect(find.text('Modifier dans Documents'), findsNothing); // not editable
    await shot(tester, '61_share_pdf');
  });

  testWidgets('several shared files are offered together', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('share_ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final n in ['a.jpg', 'b.jpg']) {
      File('${tmp.path}/$n').writeAsBytesSync(List.filled(1500000, 1));
    }
    await start(
      tester,
      Incoming(
        files: [
          IncomingFile('${tmp.path}/a.jpg', 'a.jpg', 'image/jpeg'),
          IncomingFile('${tmp.path}/b.jpg', 'b.jpg', 'image/jpeg'),
        ],
      ),
    );
    expect(find.textContaining('2 fichiers · 3,0 Mo'), findsOneWidget);
    expect(find.text('Enregistrer dans Images'), findsOneWidget);
    expect(find.text('Enregistrer dans Téléchargements'), findsOneWidget);
  });
}
