class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.duration,
    required this.uri,
    this.path = '',
    this.track = 0,
    this.dateAdded = 0,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final int albumId;
  final Duration duration;

  /// content:// address handed to the player.
  final String uri;
  final String path;
  final int track;

  /// Seconds since epoch.
  final int dateAdded;

  static Song fromMap(Map<Object?, Object?> m) {
    String text(String key, String fallback) {
      final v = (m[key] as String?)?.trim() ?? '';
      return v.isEmpty || v == '<unknown>' ? fallback : v;
    }

    return Song(
      id: (m['id'] as num).toInt(),
      title: text('title', 'Titre inconnu'),
      artist: text('artist', 'Artiste inconnu'),
      album: text('album', 'Album inconnu'),
      albumId: (m['albumId'] as num?)?.toInt() ?? 0,
      duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
      uri: m['uri'] as String,
      path: (m['path'] as String?) ?? '',
      // MediaStore encodes disc and track as DTTT.
      track: ((m['track'] as num?)?.toInt() ?? 0) % 1000,
      dateAdded: (m['dateAdded'] as num?)?.toInt() ?? 0,
    );
  }

  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      artist.toLowerCase().contains(query) ||
      album.toLowerCase().contains(query);
}

/// A named group of songs: an album or an artist.
class SongGroup {
  SongGroup(this.name, this.subtitle, this.songs);
  final String name;
  final String subtitle;
  final List<Song> songs;

  Duration get duration =>
      songs.fold(Duration.zero, (sum, s) => sum + s.duration);
}

List<SongGroup> groupByAlbum(List<Song> songs) {
  final map = <int, List<Song>>{};
  for (final s in songs) {
    map.putIfAbsent(s.albumId, () => []).add(s);
  }
  return [
    for (final list in map.values)
      SongGroup(
        list.first.album,
        list.every((s) => s.artist == list.first.artist)
            ? list.first.artist
            : 'Artistes variés',
        list..sort((a, b) => a.track.compareTo(b.track)),
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

List<SongGroup> groupByArtist(List<Song> songs) {
  final map = <String, List<Song>>{};
  for (final s in songs) {
    map.putIfAbsent(s.artist, () => []).add(s);
  }
  return [
    for (final e in map.entries)
      SongGroup(
        e.key,
        '${e.value.length} titre${e.value.length > 1 ? 's' : ''}',
        e.value,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Sort modes of the library: 0 by title, 1 most recently added, 2 by
/// artist then title.
List<Song> sortSongs(List<Song> songs, int mode) {
  final list = [...songs];
  switch (mode) {
    case 1:
      list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    case 2:
      list.sort((a, b) {
        final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        return c != 0
            ? c
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    default:
      list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
  }
  return list;
}
