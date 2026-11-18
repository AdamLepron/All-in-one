import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';
import '../music/music_controller.dart';
import '../music/song.dart';
import 'online.dart';

/// What the user keeps from the online part of the app: favourite stations,
/// followed podcasts, which episodes were heard and which are downloaded.
/// Everything stays on the phone (and in backups, as preferences).
class OnlineLibrary {
  OnlineLibrary(this._settings);
  final AppSettings _settings;

  static const _favKey = 'radioFavorites';
  static const _subKey = 'podcastSubs';
  static const _playedKey = 'podcastPlayed';
  static const _dlKey = 'podcastDownloads';

  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) from) {
    final raw = _settings.raw(key);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          from(j as Map<String, dynamic>),
      ];
    } on Object {
      return [];
    }
  }

  // ---- Stations ----

  List<RadioStation> get favoriteStations =>
      _readList(_favKey, RadioStation.fromJson);

  bool isFavorite(RadioStation s) =>
      favoriteStations.any((f) => f.url == s.url);

  void toggleFavorite(RadioStation s) {
    final list = favoriteStations;
    final exists = list.any((f) => f.url == s.url);
    final next = exists
        ? [
            for (final f in list)
              if (f.url != s.url) f,
          ]
        : [...list, s];
    _settings.setRaw(_favKey, jsonEncode([for (final f in next) f.toJson()]));
  }

  // ---- Podcasts ----

  List<Podcast> get subscriptions => _readList(_subKey, Podcast.fromJson);

  bool isSubscribed(Podcast p) => subscriptions.any((s) => s.feed == p.feed);

  void toggleSubscription(Podcast pod) {
    final list = subscriptions;
    final exists = list.any((s) => s.feed == pod.feed);
    final next = exists
        ? [
            for (final s in list)
              if (s.feed != pod.feed) s,
          ]
        : [...list, pod];
    _settings.setRaw(_subKey, jsonEncode([for (final s in next) s.toJson()]));
  }

  Set<String> get _played {
    final raw = _settings.raw(_playedKey);
    if (raw == null) return {};
    try {
      return {for (final g in jsonDecode(raw) as List) g as String};
    } on Object {
      return {};
    }
  }

  bool isPlayed(Episode e) => _played.contains(e.guid);

  void setPlayed(Episode e, bool played) {
    final set = _played;
    played ? set.add(e.guid) : set.remove(e.guid);
    // Only the most recent 3,000 are kept: the list must not grow forever.
    final list = set.toList();
    final kept = list.length > 3000 ? list.sublist(list.length - 3000) : list;
    _settings.setRaw(_playedKey, jsonEncode(kept));
  }

  // ---- Downloads ----

  Map<String, String> get _downloads {
    final raw = _settings.raw(_dlKey);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          e.key as String: e.value as String,
      };
    } on Object {
      return {};
    }
  }

  /// Path of the downloaded file of [e], if it is still on the phone.
  String? downloadedPath(Episode e) {
    final path = _downloads[e.guid];
    return path != null && File(path).existsSync() ? path : null;
  }

  void _setDownload(Episode e, String? path) {
    final map = _downloads;
    path == null ? map.remove(e.guid) : map[e.guid] = path;
    _settings.setRaw(_dlKey, jsonEncode(map));
  }

  /// Where downloaded episodes are kept; tests replace it.
  static Future<String> Function() locate = () async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'podcasts');

  /// Downloads [e] for offline listening. [onProgress] gets 0–1 when the
  /// size is known. Returns the file path.
  Future<String> download(
    Episode e, {
    void Function(double fraction)? onProgress,
    HttpClient? client,
  }) async {
    final dir = Directory(await locate());
    await dir.create(recursive: true);
    final ext = () {
      final e2 = p.extension(Uri.parse(e.audio).path).toLowerCase();
      return const {
            '.mp3',
            '.m4a',
            '.aac',
            '.ogg',
            '.opus',
            '.wav',
          }.contains(e2)
          ? e2
          : '.mp3';
    }();
    final name =
        '${sha1.convert(utf8.encode(e.guid)).toString().substring(0, 16)}$ext';
    final target = File(p.join(dir.path, name));
    final partial = File('${target.path}.part');
    final http =
        client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 10));
    try {
      final request = await http.getUrl(Uri.parse(e.audio));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var got = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress?.call(got / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got < total) {
        throw const HttpException('Téléchargement interrompu');
      }
      await partial.rename(target.path);
      _setDownload(e, target.path);
      return target.path;
    } on Object {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  Future<void> deleteDownload(Episode e) async {
    final path = _downloads[e.guid];
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    _setDownload(e, null);
  }
}

/// A song-shaped entry for something that is streamed, so the music player,
/// its notification and the equalizer handle it like any other sound.
Song streamSong({
  required String key,
  required String title,
  required String artist,
  required String album,
  required String uri,
  Duration duration = Duration.zero,
}) => Song(
  // Negative ids never collide with the media library.
  id: -(key.hashCode.abs() + 1),
  title: title,
  artist: artist,
  album: album,
  albumId: -1,
  duration: duration,
  uri: uri,
);

Future<void> playStation(MusicController music, RadioStation s) => music.play(
  [
    streamSong(
      key: 'radio:${s.url}',
      title: s.name,
      artist: 'Radio',
      album: s.country.isEmpty ? 'Radio' : s.country,
      uri: s.url,
    ),
  ],
  0,
  shuffled: false,
);

Future<void> playEpisode(
  MusicController music,
  Podcast podcast,
  Episode e, {
  String? localPath,
}) => music.play(
  [
    streamSong(
      key: 'episode:${e.guid}',
      title: e.title,
      artist: podcast.title,
      album: 'Podcast',
      uri: localPath != null ? Uri.file(localPath).toString() : e.audio,
      duration: e.duration,
    ),
  ],
  0,
  shuffled: false,
);
