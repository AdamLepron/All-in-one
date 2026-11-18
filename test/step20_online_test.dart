import 'package:all_in_one/modules/radio/online.dart';
import 'package:flutter_test/flutter_test.dart';

const rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>Le Podcast &amp; Cie</title>
  <itunes:author>Radio Exemple</itunes:author>
  <itunes:image href="https://ex.fr/art.jpg"/>
  <item>
    <title>Ancien épisode</title>
    <guid>ep-1</guid>
    <pubDate>Mon, 01 Jan 2024 10:00:00 +0100</pubDate>
    <itunes:duration>12:30</itunes:duration>
    <description><![CDATA[<p>Un <b>résumé</b> &amp; plus</p>]]></description>
    <enclosure url="https://ex.fr/1.mp3" length="1234567" type="audio/mpeg"/>
  </item>
  <item>
    <title>Récent</title>
    <pubDate>Wed, 10 Jan 2024 06:00:00 GMT</pubDate>
    <itunes:duration>3723</itunes:duration>
    <enclosure url="https://ex.fr/2.mp3" type="audio/mpeg"/>
  </item>
  <item>
    <title>Sans audio</title>
    <guid>ep-3</guid>
  </item>
</channel></rss>''';

void main() {
  group('radio', () {
    const body = '''[
      {"stationuuid":"a","name":"  Radio Un ","url_resolved":"https://s.ex/un","favicon":"https://ex/u.png","country":"France","tags":"pop,rock","codec":"MP3","bitrate":128},
      {"stationuuid":"b","name":"Doublon","url_resolved":"https://s.ex/un"},
      {"stationuuid":"c","name":"","url_resolved":"https://s.ex/vide"},
      {"stationuuid":"d","name":"FTP","url_resolved":"ftp://s.ex/x"},
      {"stationuuid":"e","name":"Deux","url_resolved":"http://s.ex/deux"}
    ]''';

    test('usable stations only, duplicates removed', () {
      final list = parseStations(body);
      expect(list.map((s) => s.name), ['Radio Un', 'Deux']);
      expect(list.first.bitrate, 128);
      expect(list.first.tags, 'pop,rock');
      expect(parseStations('pas du json'), isEmpty);
      expect(parseStations('{"a":1}'), isEmpty);
    });

    test('a station survives being saved and read back', () {
      final s = parseStations(body).first;
      final back = RadioStation.fromJson(s.toJson());
      expect(
        (back.id, back.name, back.url, back.logo),
        (s.id, s.name, s.url, s.logo),
      );
    });

    test(
      'search asks the directory, then a second server if the first fails',
      () async {
        final asked = <Uri>[];
        final dir = RadioDirectory(
          get: (uri) async {
            asked.add(uri);
            if (uri.host.startsWith('de1')) throw Exception('down');
            return body;
          },
        );
        final r = await dir.search(name: 'jazz', countryCode: 'FR');
        expect(r, hasLength(2));
        expect(asked.map((u) => u.host), [
          'de1.api.radio-browser.info',
          'fi1.api.radio-browser.info',
        ]);
        final q = asked.last.queryParameters;
        expect(
          (q['name'], q['countrycode'], q['hidebroken']),
          ('jazz', 'FR', 'true'),
        );
        // No name and no country: neither parameter is sent.
        await dir.search();
        expect(asked.last.queryParameters.containsKey('name'), isFalse);
        expect(asked.last.queryParameters.containsKey('countrycode'), isFalse);
      },
    );

    test('every server down: the error is reported', () async {
      final dir = RadioDirectory(get: (_) async => throw Exception('offline'));
      await expectLater(dir.search(name: 'x'), throwsException);
    });
  });

  group('podcast search', () {
    test('keeps results that have a feed', () {
      final list = parsePodcastSearch('''{"resultCount":3,"results":[
        {"collectionName":"Histoire","artistName":"Radio","feedUrl":"https://ex.fr/feed","artworkUrl100":"https://ex.fr/100.jpg","artworkUrl600":"https://ex.fr/600.jpg"},
        {"collectionName":"Sans flux","artistName":"X"},
        {"collectionName":"","feedUrl":"https://ex.fr/vide"}
      ]}''');
      expect(list, hasLength(1));
      expect(
        (list.single.title, list.single.feed, list.single.art),
        ('Histoire', 'https://ex.fr/feed', 'https://ex.fr/600.jpg'),
      );
      expect(parsePodcastSearch('x'), isEmpty);
    });
  });

  group('feeds', () {
    test('channel and episodes, newest first, ones without audio skipped', () {
      final feed = parseFeed(rss)!;
      expect(feed.title, 'Le Podcast & Cie');
      expect(feed.author, 'Radio Exemple');
      expect(feed.art, 'https://ex.fr/art.jpg');
      expect(feed.episodes.map((e) => e.title), ['Récent', 'Ancien épisode']);
      final recent = feed.episodes.first;
      expect(recent.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(recent.guid, 'https://ex.fr/2.mp3'); // no guid: the address
      expect(recent.published, DateTime.utc(2024, 1, 10, 6));
      final old = feed.episodes.last;
      expect(old.guid, 'ep-1');
      expect(old.published, DateTime.utc(2024, 1, 1, 9)); // +0100 → UTC
      expect(old.duration, const Duration(minutes: 12, seconds: 30));
      expect(old.summary, 'Un résumé & plus');
      expect(old.size, 1234567);
      expect(old.playable, isTrue);
    });

    test('not a feed, broken XML', () {
      expect(parseFeed('<html><body>hello</body></html>'), isNull);
      expect(parseFeed('<rss><channel>'), isNull);
      expect(parseFeed(''), isNull);
    });

    test('durations and dates in their various forms', () {
      expect(parseDuration('754'), const Duration(seconds: 754));
      expect(
        parseDuration('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(parseDuration('00:45'), const Duration(seconds: 45));
      expect(parseDuration('abc'), Duration.zero);
      expect(parseDuration(null), Duration.zero);
      expect(
        parseFeedDate('Tue, 02 Jan 2024 08:00:00 -0500'),
        DateTime.utc(2024, 1, 2, 13),
      );
      expect(
        parseFeedDate('2 Jan 2024 08:00 GMT'),
        DateTime.utc(2024, 1, 2, 8),
      );
      expect(
        parseFeedDate('2024-01-02T08:00:00Z'),
        DateTime.utc(2024, 1, 2, 8),
      );
      expect(parseFeedDate('hier'), isNull);
      expect(parseFeedDate(null), isNull);
    });
  });

  test('service: search builds the query; a non-feed is an error', () async {
    Uri? seen;
    final service = PodcastService(
      get: (uri) async {
        seen = uri;
        return uri.host == 'itunes.apple.com' ? '{"results":[]}' : '<html/>';
      },
    );
    await service.search('  histoire ');
    expect(seen!.queryParameters['term'], 'histoire');
    expect(seen!.queryParameters['media'], 'podcast');
    await expectLater(
      service.feed('https://ex.fr/pas-un-flux'),
      throwsFormatException,
    );
  });
}
