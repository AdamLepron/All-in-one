import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

/// Reads a web address and returns the body, or throws.
typedef HttpGet = Future<String> Function(Uri uri);

/// Plain GET with short timeouts. Only what the user searched for or
/// subscribed to is requested; no account, no identifier is sent.
Future<String> httpGetText(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'All-in-One/2.0';
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 10));
    request.followRedirects = true;
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    // Feeds can be large: the first 6 MB are enough for the recent episodes.
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 6 * 1024 * 1024) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}

// ---- Radio ----

/// A radio station of the community directory (radio-browser.info).
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.logo = '',
    this.country = '',
    this.tags = '',
    this.codec = '',
    this.bitrate = 0,
  });

  final String id;
  final String name;

  /// Direct address of the audio stream.
  final String url;
  final String logo;
  final String country;
  final String tags;
  final String codec;
  final int bitrate;

  /// Only streams over HTTP(S) are played.
  bool get playable {
    final u = Uri.tryParse(url);
    return u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'logo': logo,
    'country': country,
    'tags': tags,
    'codec': codec,
    'bitrate': bitrate,
  };

  static RadioStation fromJson(Map<String, dynamic> j) => RadioStation(
    id: (j['id'] ?? j['stationuuid'] ?? j['url'] ?? '') as String,
    name: ((j['name'] as String?) ?? '').trim(),
    url: ((j['url'] ?? j['url_resolved'] ?? '') as String).trim(),
    logo: ((j['logo'] ?? j['favicon'] ?? '') as String).trim(),
    country: (j['country'] as String?) ?? '',
    tags: (j['tags'] as String?) ?? '',
    codec: (j['codec'] as String?) ?? '',
    bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
  );
}

/// Stations out of the directory's JSON answer; unusable ones are dropped.
List<RadioStation> parseStations(String body) {
  try {
    final list = jsonDecode(body) as List;
    final seen = <String>{};
    return [
      for (final j in list)
        if (j is Map<String, dynamic>)
          ...() {
            final s = RadioStation.fromJson(j);
            // The same station is often listed twice under one stream.
            return s.name.isNotEmpty && s.playable && seen.add(s.url)
                ? [s]
                : const <RadioStation>[];
          }(),
    ];
  } on Object {
    return const [];
  }
}

/// Searches the open radio directory.
class RadioDirectory {
  RadioDirectory({HttpGet? get}) : _get = get ?? httpGetText;
  final HttpGet _get;

  static const _hosts = [
    'de1.api.radio-browser.info',
    'fi1.api.radio-browser.info',
  ];

  /// Stations matching [name] (may be empty to list the most listened),
  /// optionally limited to a two-letter [countryCode].
  Future<List<RadioStation>> search({
    String name = '',
    String? countryCode,
    int limit = 40,
  }) async {
    final query = {
      if (name.trim().isNotEmpty) 'name': name.trim(),
      'countrycode': ?countryCode,
      'limit': '$limit',
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
    };
    Object? last;
    for (final host in _hosts) {
      try {
        final body = await _get(
          Uri.https(host, '/json/stations/search', query),
        );
        return parseStations(body);
      } on Object catch (e) {
        last = e; // try the next server
      }
    }
    throw last ?? const HttpException('Annuaire indisponible');
  }
}

// ---- Podcasts ----

/// A podcast the user can follow.
class Podcast {
  const Podcast({
    required this.title,
    required this.feed,
    this.author = '',
    this.art = '',
  });

  final String title;

  /// Address of the RSS feed.
  final String feed;
  final String author;
  final String art;

  Map<String, Object> toJson() => {
    'title': title,
    'feed': feed,
    'author': author,
    'art': art,
  };

  static Podcast fromJson(Map<String, dynamic> j) => Podcast(
    title: (j['title'] as String?) ?? '',
    feed: (j['feed'] as String?) ?? '',
    author: (j['author'] as String?) ?? '',
    art: (j['art'] as String?) ?? '',
  );
}

/// Podcasts out of an iTunes Search answer.
List<Podcast> parsePodcastSearch(String body) {
  try {
    final results = (jsonDecode(body) as Map)['results'] as List;
    return [
      for (final r in results)
        if (r is Map &&
            r['feedUrl'] is String &&
            (r['feedUrl'] as String).startsWith('http'))
          Podcast(
            title: ((r['collectionName'] ?? r['trackName'] ?? '') as String)
                .trim(),
            feed: r['feedUrl'] as String,
            author: (r['artistName'] as String?) ?? '',
            art: ((r['artworkUrl600'] ?? r['artworkUrl100'] ?? '') as String),
          ),
    ].where((p) => p.title.isNotEmpty).toList();
  } on Object {
    return const [];
  }
}

/// One episode of a podcast.
class Episode {
  const Episode({
    required this.guid,
    required this.title,
    required this.audio,
    this.published,
    this.duration = Duration.zero,
    this.summary = '',
    this.size = 0,
  });

  /// Stable identity, to remember what was heard.
  final String guid;
  final String title;
  final String audio;
  final DateTime? published;
  final Duration duration;
  final String summary;
  final int size;

  /// Only audio and video enclosures over HTTP(S).
  bool get playable =>
      audio.startsWith('http://') || audio.startsWith('https://');
}

/// A parsed feed.
class Feed {
  const Feed(this.title, this.author, this.art, this.episodes);
  final String title;
  final String author;
  final String art;

  /// Newest first.
  final List<Episode> episodes;
}

/// "1:02:03", "12:30", "754" (seconds) → a duration.
Duration parseDuration(String? raw) {
  if (raw == null || raw.trim().isEmpty) return Duration.zero;
  final parts = raw.trim().split(':');
  try {
    final nums = [for (final p in parts) double.parse(p)];
    return switch (nums.length) {
      1 => Duration(seconds: nums[0].round()),
      2 => Duration(seconds: (nums[0] * 60 + nums[1]).round()),
      3 => Duration(seconds: (nums[0] * 3600 + nums[1] * 60 + nums[2]).round()),
      _ => Duration.zero,
    };
  } on FormatException {
    return Duration.zero;
  }
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// RFC 822 dates of RSS ("Tue, 02 Jan 2024 08:00:00 +0100", "GMT", "Z"),
/// or ISO 8601; null when unreadable.
DateTime? parseFeedDate(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc();
  final m = RegExp(
    r'(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,4})?',
  ).firstMatch(text);
  if (m == null) return null;
  final month = _months[m[2]!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m[3]!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  var d = DateTime.utc(
    year,
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.tryParse(m[6] ?? '') ?? 0,
  );
  final zone = m[7];
  if (zone != null && RegExp(r'^[+-]\d{4}$').hasMatch(zone)) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final offset = Duration(
      hours: int.parse(zone.substring(1, 3)),
      minutes: int.parse(zone.substring(3, 5)),
    );
    d = sign > 0 ? d.subtract(offset) : d.add(offset);
  }
  return d;
}

String _text(XmlElement? e) => e?.innerText.trim() ?? '';

String _plain(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Reads an RSS 2.0 podcast feed. Returns null if [body] is not a feed.
Feed? parseFeed(String body) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException {
    return null;
  }
  final channel = doc.findAllElements('channel').firstOrNull;
  if (channel == null) return null;
  XmlElement? firstChild(XmlElement parent, String name) =>
      parent.childElements.where((e) => e.name.local == name).firstOrNull;

  final art =
      channel.childElements
          .where((e) => e.name.local == 'image')
          .map((e) => e.getAttribute('href') ?? _text(firstChild(e, 'url')))
          .where((s) => s.isNotEmpty)
          .firstOrNull ??
      '';
  final episodes = <Episode>[];
  for (final item in channel.findElements('item')) {
    final enclosure = item.childElements
        .where((e) => e.name.local == 'enclosure')
        .firstOrNull;
    final url = enclosure?.getAttribute('url')?.trim() ?? '';
    if (url.isEmpty) continue;
    final title = _text(firstChild(item, 'title'));
    episodes.add(
      Episode(
        guid: _text(firstChild(item, 'guid')).isNotEmpty
            ? _text(firstChild(item, 'guid'))
            : url,
        title: title.isEmpty ? 'Épisode' : title,
        audio: url,
        published: parseFeedDate(_text(firstChild(item, 'pubDate'))),
        duration: parseDuration(_text(firstChild(item, 'duration'))),
        summary: _plain(_text(firstChild(item, 'description'))),
        size: int.tryParse(enclosure?.getAttribute('length') ?? '') ?? 0,
      ),
    );
  }
  // Most feeds are newest first already; undated ones keep their order.
  episodes.sort((a, b) {
    final da = a.published, db = b.published;
    if (da == null || db == null) return 0;
    return db.compareTo(da);
  });
  return Feed(
    _text(firstChild(channel, 'title')),
    _text(firstChild(channel, 'author')),
    art,
    episodes,
  );
}

/// Searches podcasts (Apple's public directory) and reads feeds.
class PodcastService {
  PodcastService({HttpGet? get}) : _get = get ?? httpGetText;
  final HttpGet _get;

  Future<List<Podcast>> search(String term, {String country = 'FR'}) async {
    final body = await _get(
      Uri.https('itunes.apple.com', '/search', {
        'media': 'podcast',
        'term': term.trim(),
        'country': country,
        'limit': '25',
      }),
    );
    return parsePodcastSearch(body);
  }

  /// The feed at [address]; throws if it cannot be read.
  Future<Feed> feed(String address) async {
    final feed = parseFeed(await _get(Uri.parse(address)));
    if (feed == null) {
      throw const FormatException("Ce n'est pas un flux de podcast");
    }
    return feed;
  }
}
