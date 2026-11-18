import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/radio/online.dart';
import 'package:all_in_one/modules/radio/online_library.dart';
import 'package:all_in_one/modules/radio/radio_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const station = RadioStation(
  id: 'a',
  name: 'Radio Un',
  url: 'https://s.ex/un',
  country: 'France',
  codec: 'MP3',
  bitrate: 128,
);
const pod = Podcast(title: 'Histoire', feed: 'https://ex.fr/feed');
const episode = Episode(
  guid: 'g1',
  title: 'Épisode 1',
  audio: 'https://ex.fr/1.mp3',
  duration: Duration(minutes: 30),
);

void main() {
  late AppSettings settings;
  late OnlineLibrary library;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    library = OnlineLibrary(settings);
    // The test binding blocks real network calls; these tests use a local server.
    HttpOverrides.global = null;
    tmp = Directory.systemTemp.createTempSync('step20_radio');
    OnlineLibrary.locate = () async => '${tmp.path}/podcasts';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('library', () {
    test('favourite stations toggle and survive a restart', () {
      expect(library.favoriteStations, isEmpty);
      library.toggleFavorite(station);
      expect(library.isFavorite(station), isTrue);
      expect(OnlineLibrary(settings).favoriteStations.single.name, 'Radio Un');
      library.toggleFavorite(station);
      expect(library.favoriteStations, isEmpty);
    });

    test('subscriptions and played marks', () {
      library.toggleSubscription(pod);
      expect(library.subscriptions.single.title, 'Histoire');
      expect(library.isSubscribed(pod), isTrue);
      expect(library.isPlayed(episode), isFalse);
      library.setPlayed(episode, true);
      expect(library.isPlayed(episode), isTrue);
      library.setPlayed(episode, false);
      expect(library.isPlayed(episode), isFalse);
      library.toggleSubscription(pod);
      expect(library.subscriptions, isEmpty);
    });

    test('damaged stored values read as empty', () async {
      SharedPreferences.setMockInitialValues({
        'radioFavorites': '{oops',
        'podcastSubs': '[1,2]',
        'podcastPlayed': 'x',
      });
      final s = AppSettings(await SharedPreferences.getInstance());
      final l = OnlineLibrary(s);
      expect(l.favoriteStations, isEmpty);
      expect(l.subscriptions, isEmpty);
      expect(l.isPlayed(episode), isFalse);
    });

    test(
      'streams look like songs for the player, with unique negative ids',
      () {
        final a = streamSong(
          key: 'radio:x',
          title: 'R',
          artist: 'Radio',
          album: 'FR',
          uri: 'https://s/x',
        );
        final b = streamSong(
          key: 'radio:y',
          title: 'R',
          artist: 'Radio',
          album: 'FR',
          uri: 'https://s/y',
        );
        expect(a.id, isNegative);
        expect(a.id, isNot(b.id));
        expect(a.albumId, -1); // no cover looked up in the media library
        expect(a.uri, 'https://s/x');
      },
    );
  });

  group('downloads', () {
    late HttpServer server;
    var status = 200;
    late List<int> payload;

    setUp(() async {
      payload = List.generate(50000, (i) => i % 251);
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = status;
        if (status == 200) {
          req.response.contentLength = payload.length;
          req.response.add(payload);
        }
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Episode ep(String guid) => Episode(
      guid: guid,
      title: 't',
      audio: 'http://127.0.0.1:${server.port}/a.mp3',
    );

    test('a download is saved, remembered, reported and removable', () async {
      final progress = <double>[];
      final path = await library.download(ep('g1'), onProgress: progress.add);
      expect(File(path).readAsBytesSync(), payload);
      expect(progress.last, 1.0);
      expect(library.downloadedPath(ep('g1')), path);
      expect(File('$path.part').existsSync(), isFalse);
      await library.deleteDownload(ep('g1'));
      expect(File(path).existsSync(), isFalse);
      expect(library.downloadedPath(ep('g1')), isNull);
    });

    test('a failed download leaves nothing behind', () async {
      status = 404;
      await expectLater(
        library.download(ep('g2')),
        throwsA(isA<HttpException>()),
      );
      expect(library.downloadedPath(ep('g2')), isNull);
      final dir = Directory('${tmp.path}/podcasts');
      expect(dir.existsSync() ? dir.listSync() : <FileSystemEntity>[], isEmpty);
    });

    test(
      'a file deleted by hand is no longer reported as downloaded',
      () async {
        final path = await library.download(ep('g3'));
        File(path).deleteSync();
        expect(library.downloadedPath(ep('g3')), isNull);
      },
    );
  });

  testWidgets(
    'radio tab lists stations, favourites and plays one; podcasts search and subscribe',
    (tester) async {
      final music = MusicController(settings);
      final dir = RadioDirectory(
        get: (_) async => '[{"stationuuid":"a","name":"Radio Un","url_resolved":"https://s.ex/un","country":"France","codec":"MP3","bitrate":128}]',
      );
      final service = PodcastService(
        get: (uri) async => uri.host == 'itunes.apple.com'
            ? '{"results":[{"collectionName":"Histoire","artistName":"Radio","feedUrl":"https://ex.fr/feed"}]}'
            : '''<rss><channel><title>Histoire</title><item><title>Épisode 1</title><guid>g1</guid><enclosure url="https://ex.fr/1.mp3"/></item></channel></rss>''',
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: music),
          ],
          child: MaterialApp(
            home: RadioPage(directory: dir, podcasts: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Radio Un'), findsOneWidget);
      expect(find.textContaining('128 kb/s'), findsOneWidget);

      await tester.tap(find.byTooltip('Ajouter aux favoris'));
      await tester.pumpAndSettle();
      expect(library.favoriteStations.single.name, 'Radio Un');
      expect(find.text('Mes radios'), findsOneWidget);

      // Podcasts tab.
      await tester.tap(find.text('Podcasts'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recherchez un podcast'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'histoire');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histoire').last);
      await tester.pumpAndSettle();
      expect(find.text('Épisode 1'), findsOneWidget);
      await tester.tap(find.text("S'abonner"));
      await tester.pumpAndSettle();
      expect(library.subscriptions.single.feed, 'https://ex.fr/feed');
      expect(find.text('Abonné'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
