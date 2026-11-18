import 'package:all_in_one/core/settings.dart';
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
