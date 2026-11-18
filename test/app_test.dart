import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/main.dart';
import 'package:all_in_one/modules/calendar/calendar_page.dart';
import 'package:all_in_one/modules/cleaner/cleaner_page.dart';
import 'package:all_in_one/modules/clock/clock_controller.dart';
import 'package:all_in_one/modules/clock/clock_page.dart';
import 'package:all_in_one/modules/equalizer/equalizer_controller.dart';
import 'package:all_in_one/modules/files/file_ops.dart';
import 'package:all_in_one/modules/files/files_ui.dart';
import 'package:all_in_one/modules/files/folder_page.dart';
import 'package:all_in_one/modules/gallery/media_grid.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/music/now_playing.dart';
import 'package:all_in_one/modules/music/song.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/photo/photo_page.dart';
import 'package:all_in_one/modules/qr/qr_page.dart';
import 'package:all_in_one/modules/recorder/recorder_controller.dart';
import 'package:all_in_one/modules/recorder/recorder_page.dart';
import 'package:all_in_one/modules/scanner/scan_store.dart';
import 'package:all_in_one/modules/scanner/scanner_page.dart';
import 'package:all_in_one/modules/sensors/sensors_page.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:all_in_one/modules/tasks/tasks_page.dart';
import 'package:all_in_one/modules/reader/reader_page.dart';
import 'package:all_in_one/shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Loads the real Roboto and Material Icons fonts so screenshots are readable.
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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('main flows work end to end', (tester) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late AppSettings settings;
    late NotesStore notes;
    late OrganizerStore organizer;
    late Directory tmp;
    await tester.runAsync(() async {
      await loadFonts();
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/notes.db',
      );
      notes = await NotesStore.open();
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/organizer_app.db',
      );
      organizer = await OrganizerStore.load(file: 'organizer_app.db');
      // Fixed folder name: it is displayed and must not vary between runs.
      final parent = await Directory.systemTemp.createTemp('app_test');
      tmp = await Directory('${parent.path}/Téléphone').create();
      await Directory('${tmp.path}/Photos/Vacances').create(recursive: true);
      await Directory('${tmp.path}/Documents').create();
      await File('${tmp.path}/Documents/cv.pdf').writeAsString('x' * 2400);
      await File('${tmp.path}/contrat.pdf').writeAsString('x' * 184000);
      await File('${tmp.path}/photo.jpg').writeAsString('x' * 2400000);
      await File('${tmp.path}/morceau.mp3').writeAsString('x' * 5200000);
      await File('${tmp.path}/Documents/notes.txt').writeAsString(
        'Liste de courses\n\n- Pain\n- Lait\n- Œufs\n\nPenser à rappeler le plombier avant vendredi.\n',
      );
      await File('${tmp.path}/Documents/rapport.docx')
          .writeAsString('x' * 64000);
      for (final (i, title, pages, text) in [
        (
          1,
          'Facture électricité',
          2,
          'Facture électricité novembre 2026 montant 84,20 euros',
        ),
        (
          2,
          'Contrat de location',
          5,
          'Contrat de location entre les soussignés',
        ),
      ]) {
        final dir = await Directory('${parent.path}/scans/$i')
            .create(recursive: true);
        await File('${dir.path}/scan.json').writeAsString(
          '{"title": "$title", "date": ${DateTime.now().millisecondsSinceEpoch - i * 86400000}, "pages": $pages, "text": "$text"}',
        );
      }
      await Directory('${parent.path}/recordings').create();
      await File('${parent.path}/recordings/Idée de refrain.m4a')
          .writeAsString('x' * 310000);
      await File('${parent.path}/recordings/Réunion du lundi.m4a')
          .writeAsString('x' * 2400000);
      await File('${parent.path}/recordings/index.json').writeAsString(
        '{"Idée de refrain.m4a": 38000, "Réunion du lundi.m4a": 1265000}',
      );
      await File('${tmp.path}/archive.zip').writeAsString('x' * 1200);
    });
    addTearDown(() => tmp.parent.deleteSync(recursive: true));
    final music = MusicController(settings);
    final library = MediaLibrary();

    /// Database and file calls hop between real I/O and the test's fake
    /// clock, so alternate between the two until loading spinners are gone.
    Future<void> settle() async {
      var idle = 0;
      for (var i = 0; i < 500 && idle < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final loading =
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
            tester
                .widgetList<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .any((bar) => bar.value == null);
        idle = loading ? 0 : idle + 1;
      }
      await tester.pumpAndSettle();
    }

    /// Screenshots show dates relative to today, so they are review material
    /// rather than pixel references: written with --update-goldens, never
    /// compared.
    Future<void> shot(String name) async {
      if (!autoUpdateGoldenFiles) return;
      await expectLater(
        find.byType(AllInOneApp),
        matchesGoldenFile('screenshots/$name.png'),
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: notes),
          ChangeNotifierProvider.value(value: organizer),
          ChangeNotifierProvider.value(value: music),
          ChangeNotifierProvider(
            create: (_) => EqualizerController(settings, music),
          ),
          ChangeNotifierProvider(create: (_) => FilesClipboard()),
          ChangeNotifierProvider(create: (_) => ClockController()),
          ChangeNotifierProvider(
            create: (_) =>
                ScanStore(directory: () async => '${tmp.parent.path}/scans'),
          ),
          ChangeNotifierProvider(
            create: (_) => RecorderController(
              directory: () async => '${tmp.parent.path}/recordings',
            ),
          ),
          ChangeNotifierProvider.value(value: library),
        ],
        child: const AllInOneApp(),
      ),
    );
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
      await notes.save(
        Note(
          title: 'Idées projet',
          body: 'Lecteur de musique avec mini-lecteur persistant, égaliseur par casque.',
          color: 5,
        ),
      );
      await notes.save(
        Note(
          title: 'Réunion lundi',
          body: 'Préparer la démo\nEnvoyer le compte rendu',
          color: 3,
          pinned: true,
        ),
      );
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
    // The disk search starts after a pause and does real I/O.
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('Idées projet'), findsOneWidget);
    await shot('09_search');

    // Music library with a song playing.
    Song song(
      int id,
      String title,
      String artist,
      String album,
      int albumId,
      int seconds,
    ) => Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      albumId: albumId,
      duration: Duration(seconds: seconds),
      uri: 'content://$id',
      track: id,
    );
    music.debugSetLibrary([
      song(1, 'Aube', 'Les Marées', 'Rivages', 1, 214),
      song(2, 'Brume du matin', 'Les Marées', 'Rivages', 1, 187),
      song(3, 'Cap au nord', 'Nova Lune', 'Boréal', 2, 251),
      song(4, 'Derniers feux', 'Nova Lune', 'Boréal', 2, 198),
      song(5, 'Écume', 'Les Marées', 'Rivages', 1, 233),
      song(6, 'Fragments', 'Atelier Sud', 'Esquisses', 3, 176),
    ], playingIndex: 2);
    settings.toggleFavorite(3);
    await tester.tap(find.text('Médias'));
    await tester.pumpAndSettle();
    await shot('10_media_with_player');
    await tester.tap(find.text('Musique').last);
    await tester.pumpAndSettle();
    expect(find.text('Cap au nord'), findsWidgets);
    await shot('11_music');
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await shot('12_music_albums');
    await tester.tap(find.text('Boréal'));
    await tester.pumpAndSettle();
    await shot('13_music_album');
    showNowPlaying(tester.element(find.byType(Scaffold).last));
    await tester.pumpAndSettle();
    expect(find.text('LECTURE EN COURS'), findsOneWidget);
    await shot('14_now_playing');
    await tester.tap(find.byTooltip('Réduire'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Gallery timeline, albums, viewer and video library.
    final now = DateTime.now();
    Media media(int id, int daysAgo, String album, {bool video = false}) =>
        Media(
          id: id,
          video: video,
          path: '/none/$id',
          name: video ? 'VID_$id.mp4' : 'IMG_$id.jpg',
          date: now.subtract(Duration(days: daysAgo, minutes: id)),
          uri: 'content://media/$id',
          size: video ? 48000000 : 3200000,
          width: 4000,
          height: 3000,
          album: album,
          duration: Duration(seconds: video ? 75 + id : 0),
        );
    library.debugSet([
      for (var i = 1; i <= 7; i++) media(i, 0, 'Appareil photo'),
      media(8, 0, 'Appareil photo', video: true),
      for (var i = 9; i <= 14; i++) media(i, 1, 'Captures'),
      for (var i = 15; i <= 22; i++) media(i, 40, 'Appareil photo'),
      media(23, 40, 'Téléchargements', video: true),
    ]);
    settings.setVideoPosition('v23', const Duration(seconds: 42));
    await tester.tap(find.text('Galerie').last);
    await settle();
    expect(find.text("Aujourd'hui"), findsWidgets);
    await shot('20_gallery');
    await tester.longPress(find.byType(MediaThumb).first);
    await tester.pumpAndSettle();
    await shot('21_gallery_selection');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Captures'), findsOneWidget);
    await shot('22_gallery_albums');
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MediaThumb).at(1));
    await settle();
    expect(find.text('Détails'), findsOneWidget);
    await shot('23_viewer');
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecteur vidéo').last);
    await settle();
    expect(find.text('Reprendre à 0:42'), findsOneWidget);
    await shot('24_videos');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // File manager home, then a folder with selection and trash.
    await tester.tap(find.text('Documents').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fichiers'));
    await settle();
    expect(find.text('Accès rapide'), findsOneWidget);
    await shot('15_files_home');
    await tester.pageBack();
    await tester.pumpAndSettle();

    final trash = Trash('${tmp.path}/.trash');
    Navigator.of(tester.element(find.byType(AppShell))).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FolderPage(path: tmp.path, root: tmp.path, trash: trash),
      ),
    );
    await settle();
    expect(find.text('contrat.pdf'), findsOneWidget);
    await shot('16_folder');
    await tester.longPress(find.text('contrat.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('archive.zip'));
    await tester.pumpAndSettle();
    await shot('17_folder_selection');
    await tester.tap(find.byTooltip('Supprimer'));
    await settle();
    expect(find.text('contrat.pdf'), findsNothing);
    expect(find.text('2 éléments déplacés dans la corbeille'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await settle();
    expect(find.text('contrat.pdf'), findsOneWidget);

    // Copy a file into a sub-folder.
    await tester.longPress(find.text('photo.jpg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photos'));
    await settle();
    await shot('18_folder_paste');
    await tester.tap(find.text('Coller ici'));
    await settle();
    expect(File('${tmp.path}/Photos/photo.jpg').existsSync(), true);
    expect(find.text('photo.jpg'), findsOneWidget);
    await tester.pageBack();
    await settle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Document library and text viewer.
    Navigator.of(
      tester.element(find.byType(AppShell)),
    ).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(root: tmp.path)));
    await settle();
    expect(find.text('contrat.pdf'), findsOneWidget);
    expect(find.text('rapport.docx'), findsOneWidget);
    await tester.tap(find.text('notes.txt'));
    await settle();
    expect(find.text('- Pain'), findsOneWidget);
    await shot('25_text_viewer');
    await tester.pageBack();
    await settle();
    expect(find.text('Reprendre la lecture'), findsOneWidget);
    await shot('26_documents');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Equaliser: a preset changes the bands and enables the effect.
    await tester.tap(find.text('Médias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Égaliseur').last);
    await tester.pumpAndSettle();
    final eq = tester.element(find.text('Balance')).read<EqualizerController>();
    expect(eq.enabled, false);
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(eq.enabled, true);
    expect(eq.preset, 'Rock');
    expect(eq.levels.first, greaterThan(0));
    eq.setBalance(-0.3);
    await tester.pumpAndSettle();
    expect(find.text('Gauche 30 %'), findsOneWidget);
    await shot('27_equalizer');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Step 5 tools, each opened directly.
    Future<void> open(Widget page) async {
      // Test time does not flow, so messages would stay over the buttons.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(AppShell)))
          .push(MaterialPageRoute<void>(builder: (_) => page));
      await settle();
    }

    Future<void> close() async {
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    await open(const QrPage(initialTab: 1));
    await tester.enterText(
      find.byType(TextField).first,
      'https://exemple.fr/menu',
    );
    await tester.pumpAndSettle();
    expect(find.text("Partager l'image"), findsOneWidget);
    await shot('28_qr_create');
    await close();

    await open(const ClockPage());
    expect(find.text('Dans le monde'), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    await shot('29_clock');
    await tester.tap(find.text('Minuteur'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('10 min'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('10:00'), findsOneWidget);
    await shot('30_timer');
    await tester.tap(find.text('Chronomètre'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('00:00,00'), findsOneWidget);
    await shot('31_stopwatch');
    await close();

    await open(const SensorsPage());
    expect(find.text('Éteinte'), findsOneWidget);
    await shot('32_torch');
    await tester.tap(find.text('Règle'));
    await settle();
    await shot('33_ruler');
    await close();

    await open(const RecorderPage());
    expect(find.text('Réunion du lundi'), findsOneWidget);
    expect(find.textContaining('21:05'), findsOneWidget);
    await shot('34_recorder');
    await close();

    // Tasks: quick add understands dates, completing moves the task.
    await open(const TasksPage());
    expect(find.text("Rien de prévu aujourd'hui"), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'Appeler le plombier demain 9h urgent',
    );
    await tester.pump();
    expect(
      find.text('Demain 9:00'),
      findsOneWidget,
    ); // preview of what was understood
    await shot('35_tasks_quick_add');
    await tester.tap(find.byTooltip('Ajouter'));
    await settle();
    expect(organizer.open.single.title, 'Appeler le plombier');
    expect(organizer.open.single.priority, 3);
    final today = dayOf(DateTime.now());
    await tester.runAsync(() async {
      await organizer.saveTask(
        Task(title: 'Envoyer le devis', due: today, priority: 2),
      );
      await organizer.saveTask(
        Task(title: 'Arroser les plantes', due: today, repeat: Repeat.weekly),
      );
      await organizer.saveTask(
        Task(
          title: 'Renouveler le passeport',
          due: today.subtract(const Duration(days: 2)),
          list: 'Administratif',
        ),
      );
      await organizer.saveEvent(
        Event(
          title: "Réunion d'équipe",
          start: today.add(const Duration(hours: 14)),
          end: today.add(const Duration(hours: 15)),
          location: 'Salle Vauban',
          color: 4,
        ),
      );
      await organizer.saveEvent(
        Event(
          title: 'Week-end à Lyon',
          start: today.add(const Duration(days: 4)),
          end: today.add(const Duration(days: 6)),
          allDay: true,
          color: 1,
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('En retard'), findsOneWidget);
    await shot('36_tasks_today');
    await tester.tap(find.byTooltip('Terminer').last);
    await settle();
    expect(organizer.completed.length, 1);
    await close();

    await open(const CalendarPage());
    expect(find.text("Réunion d'équipe"), findsOneWidget);
    await shot('37_calendar_month');
    await tester.tap(find.byTooltip('Changer de vue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();
    expect(find.text('Week-end à Lyon'), findsWidgets);
    await shot('38_calendar_agenda');
    await tester.tap(find.byTooltip('Nouvel événement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Dîner chez Léa');
    await tester.pumpAndSettle();
    await shot('39_event_editor');
    await tester.tap(find.text('Enregistrer'));
    await settle();
    expect(organizer.events.map((e) => e.title), contains('Dîner chez Léa'));
    await close();

    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();
    expect(find.text("Aujourd'hui"), findsWidgets);
    expect(find.text("Réunion d'équipe"), findsOneWidget);
    await shot('40_home_today');

    // Scanner library: search looks inside the recognised text.
    await open(const ScannerPage());
    expect(find.text('Contrat de location'), findsOneWidget);
    await shot('41_scanner');
    await tester.enterText(find.byType(TextField), 'euros');
    await tester.pumpAndSettle();
    expect(find.text('Facture électricité'), findsOneWidget);
    expect(find.text('Contrat de location'), findsNothing);
    await close();

    // Cleaner on a folder with duplicates and an old download.
    final junk = await tester.runAsync(() async {
      final dir = await Directory('${tmp.parent.path}/Stockage').create();
      await Directory('${dir.path}/Photos/Sauvegarde').create(recursive: true);
      await Directory('${dir.path}/Download').create();
      await File('${dir.path}/Photos/vacances.jpg')
          .writeAsString('p' * 3400000);
      await File('${dir.path}/Photos/Sauvegarde/vacances.jpg')
          .writeAsString('p' * 3400000);
      await File('${dir.path}/Download/vacances (1).jpg')
          .writeAsString('p' * 3400000);
      final old = File('${dir.path}/Download/notice.pdf');
      await old.writeAsString('n' * 1800000);
      await old.setLastModified(
        DateTime.now().subtract(const Duration(days: 200)),
      );
      await File('${dir.path}/Download/jeu.apk').writeAsString('a' * 62000000);
      await File('${dir.path}/journal.log').writeAsString('l' * 240000);
      return dir;
    });
    await open(
      CleanerPage(
        root: junk!.path,
        trash: Trash('${junk.path}/.AllInOneTrash'),
      ),
    );
    expect(find.text('Doublons'), findsOneWidget);
    expect(find.text('Gros fichiers'), findsOneWidget);
    await shot('42_cleaner');
    await tester.tap(find.text('Doublons'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Original'), findsOneWidget);
    await shot('43_cleaner_review');
    await tester.tap(find.text('Mettre à la corbeille'));
    await settle();
    expect(
      File('${junk.path}/Photos/vacances.jpg').existsSync(),
      true,
    ); // original kept
    expect(File('${junk.path}/Download/vacances (1).jpg').existsSync(), false);
    expect(find.text('Doublons'), findsNothing);
    expect(find.textContaining('Corbeille ·'), findsOneWidget);
    await shot('44_cleaner_after');
    await close();

    // Photo editor module: lists the library's photos, not its videos.
    await open(const PhotoPage());
    expect(
      find.textContaining("L'original n'est jamais modifié"),
      findsOneWidget,
    );
    expect(
      find.byType(MediaThumb),
      findsNWidgets(library.items.where((m) => !m.video).length),
    );
    await close();

    // Dark AMOLED theme.
    settings
      ..themeMode = ThemeMode.dark
      ..amoled = true
      ..accentIndex = 1;
    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();
    await shot('19_home_dark');
  });
}
