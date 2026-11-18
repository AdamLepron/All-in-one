import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/equalizer/equalizer_controller.dart';
import 'package:all_in_one/modules/music/lyrics_page.dart';
import 'package:all_in_one/modules/music/now_playing.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/music/music_page.dart';
import 'package:all_in_one/modules/music/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song song(int id, String title) => Song(
  id: id,
  title: title,
  artist: 'Artiste',
  album: 'Album',
  albumId: 1,
  duration: const Duration(minutes: 3),
  uri: 'content://$id',
  track: id,
);

void main() {
  lyricsAndPlayerTests();
  late AppSettings settings;
  late MusicController music;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    music = MusicController(settings);
  });

  test('playlists: create, add without duplicates, remove, rename, delete', () {
    final a = settings.createPlaylist('Route', songId: 1);
    final b = settings.createPlaylist('  ');
    expect(a.id, isNot(b.id));
    expect(b.name, 'Playlist ${b.id}'); // blank name gets a default
    settings.addToPlaylist(a.id, 2);
    settings.addToPlaylist(a.id, 2); // already there
    expect(settings.playlists.first.songIds, [1, 2]);
    settings.removeFromPlaylist(a.id, 1);
    expect(settings.playlists.first.songIds, [2]);
    settings.renamePlaylist(a.id, 'Sport');
    settings.renamePlaylist(a.id, '   '); // ignored
    expect(settings.playlists.first.name, 'Sport');
    settings.deletePlaylist(b.id);
    expect(settings.playlists.map((p) => p.name), ['Sport']);
    // Ids never collide after a deletion.
    expect(settings.createPlaylist('Z').id, isNot(a.id));
  });

  test('a damaged playlist value is ignored, not fatal', () async {
    SharedPreferences.setMockInitialValues({'playlists': '{not json'});
    final s = AppSettings(await SharedPreferences.getInstance());
    expect(s.playlists, isEmpty);
    expect(s.createPlaylist('Neuve').songIds, isEmpty);
  });

  testWidgets('sleep timer fires once and clears itself; can be cancelled', (
    tester,
  ) async {
    music.setSleepTimer(const Duration(minutes: 15));
    expect(music.sleepAt.value, isNotNull);
    await tester.pump(const Duration(minutes: 14));
    expect(music.sleepAt.value, isNotNull);
    await tester.pump(const Duration(minutes: 2));
    expect(music.sleepAt.value, isNull);

    music.setSleepTimer(const Duration(minutes: 5));
    music.setSleepTimer(null);
    expect(music.sleepAt.value, isNull);
    await tester.pump(const Duration(minutes: 10)); // nothing left to fire
  });

  testWidgets('add a song to a new playlist, open it, remove the song', (
    tester,
  ) async {
    music.debugSetLibrary([song(1, 'Aube'), song(2, 'Brume')]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: music),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const MusicPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Créez une playlist'), findsOneWidget);

    await tester.tap(find.text('Titres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter à une playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Réveil');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(settings.playlists.single.name, 'Réveil');
    expect(settings.playlists.single.songIds, hasLength(1));

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réveil'));
    await tester.pumpAndSettle();
    final title = settings.playlists.single.songIds.single == 1
        ? 'Aube'
        : 'Brume';
    expect(find.text(title), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SongTile),
        matching: find.byTooltip('Options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer de la playlist'));
    await tester.pumpAndSettle();
    expect(settings.playlists.single.songIds, isEmpty);
    expect(find.textContaining('Playlist vide'), findsOneWidget);
  });
}

void lyricsAndPlayerTests() {
  testWidgets('now playing fits a narrow phone; lyrics page follows the song', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final music = MusicController(settings);
    final dir = Directory.systemTemp.createTempSync('lyr');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/aube.lrc').writeAsStringSync(
      '[00:00.00]Premier vers\n[00:30.00]Second vers\n[01:00.00]Troisième',
    );
    final s = Song(
      id: 1,
      title: 'Aube',
      artist: 'A',
      album: 'B',
      albumId: 1,
      duration: const Duration(minutes: 3),
      uri: 'content://1',
      path: '${dir.path}/aube.mp3',
    );
    music.debugSetLibrary([s], playingIndex: 0);
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: music),
        ChangeNotifierProvider(
          create: (_) => EqualizerController(settings, music),
        ),
      ],
      child: MaterialApp(home: home),
    );
    await tester.pumpWidget(app(const Scaffold(body: NowPlaying())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Paroles'), findsOneWidget);

    await tester.pumpWidget(app(const LyricsPage()));
    await tester.pump(); // starts loading the file
    for (var k = 0; k < 40; k++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Premier vers').evaluate().isNotEmpty) break;
    }
    expect(find.text('Premier vers'), findsOneWidget);
    // Moving to 31 s highlights the second line (it becomes bold/larger).
    music.position.value = const Duration(seconds: 31);
    await tester.pump(const Duration(milliseconds: 500));
    final second = tester.widget<Text>(find.text('Second vers'));
    expect(second.style?.fontSize, 22);
  });
}
