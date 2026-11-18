import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/core/util.dart';
import 'package:all_in_one/modules/gallery/media_grid.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/music/music_page.dart';
import 'package:all_in_one/modules/music/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Media> photos(int n, {int perDay = 10}) => [
  for (var i = 0; i < n; i++)
    Media(
      id: i,
      video: false,
      path: '/p/$i',
      name: 'IMG_$i',
      date: DateTime(2018).add(Duration(days: i ~/ perDay, hours: i % perDay)),
      uri: 'content://$i',
      album: 'A',
    ),
]..sort((a, b) => b.date.compareTo(a.date));

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  test('timeline lines split by day and by column count', () {
    final items = photos(25, perDay: 10); // 10 + 10 + 5 over three days
    final lines = buildTimeline(items, 4);
    // Each day: a heading, then rows of at most 4.
    expect(lines.where((l) => l.isHeader).length, 3);
    final cells = lines.where((l) => !l.isHeader).toList();
    // Newest first: the 5-photo day, then two days of 10.
    expect(cells.map((l) => l.end - l.start), [4, 1, 4, 4, 2, 4, 4, 2]);
    // Every photo appears exactly once, in order.
    final covered = [
      for (final l in cells)
        ...List.generate(l.end - l.start, (k) => l.start + k),
    ];
    expect(covered, List.generate(25, (i) => i));
    expect(buildTimeline(const [], 4), isEmpty);
    // A row never mixes two days.
    for (var i = 1; i < lines.length; i++) {
      if (!lines[i].isHeader) expect(lines[i].label, lines[i - 1].label);
    }
  });

  testWidgets('a 30,000 photo timeline scrolls quickly and shows the day', (
    tester,
  ) async {
    final items = photos(30000);
    final selection = MediaSelection();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: MediaGrid(items: items, selection: selection),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final first = items.first.date;
    expect(find.text(dayLabel(first)), findsWidgets);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
    }
    // The old per-day sections took about 170 ms per frame here.
    // ignore: avoid_print
    print('PERF ms per scroll frame: ${sw.elapsedMilliseconds / 20}');
    expect(
      sw.elapsedMilliseconds / 20,
      lessThan(60),
      reason: 'ms per scroll frame',
    );

    // The heading kept at the top follows the scrolling.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -50000));
    await tester.pump();
    await tester.pump();
    expect(find.text(dayLabel(first)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the music library shows 50,000 songs without building them all',
    (tester) async {
      final music = MusicController(settings);
      music.debugSetLibrary([
        for (var i = 0; i < 50000; i++)
          Song(
            id: i,
            title: 'Titre ${(i * 7919) % 50000}',
            artist: 'Artiste ${i % 2000}',
            album: 'Album ${i % 5000}',
            albumId: i % 5000,
            duration: const Duration(seconds: 200),
            uri: 'content://$i',
            dateAdded: i,
          ),
      ]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: music),
          ],
          child: const MaterialApp(home: MusicPage()),
        ),
      );
      final sw = Stopwatch()..start();
      await tester.pump();
      await tester.tap(find.text('Titres'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Titre 0'), findsWidgets);
      expect(find.byType(ListTile).evaluate().length, lessThan(40));
      // Sorting happens once; a second request returns the same list.
      final first = music.sortedSongs(0);
      expect(identical(first, music.sortedSongs(0)), true);
      expect(music.sortedSongs(1).first.dateAdded, 49999);
      expect(identical(music.albums, music.albums), true);
      expect(music.albums.length, 5000);
      // Changing the library drops the cached results.
      music.songs = music.songs.take(10).toList();
      expect(music.sortedSongs(0).length, 10);
      expect(music.albums.length, lessThan(11));
      expect(sw.elapsedMilliseconds, lessThan(5000));
    },
  );

  test('derived photo lists are cached until the library changes', () {
    final lib = MediaLibrary();
    lib.debugSet([
      ...photos(1000),
      Media(
        id: 9999,
        video: true,
        path: '/v',
        name: 'v',
        date: DateTime(2026),
        uri: 'content://v',
        album: 'B',
      ),
    ]);
    expect(lib.videos.length, 1);
    expect(identical(lib.videos, lib.videos), true);
    expect(identical(lib.albums, lib.albums), true);
    expect(lib.albums.map((a) => a.name).toSet(), {'A', 'B'});
    lib.forget(lib.videos);
    expect(lib.videos, isEmpty);
    expect(lib.albums.map((a) => a.name).toSet(), {'A'});
  });
}
