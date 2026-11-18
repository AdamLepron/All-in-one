import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import 'song.dart';

enum LibraryStatus { unknown, loading, denied, ready }

enum RepeatSetting { off, all, one }

/// Owns the music library and the single audio player of the app.
class MusicController extends ChangeNotifier {
  MusicController(this.settings);

  final AppSettings settings;

  LibraryStatus status = LibraryStatus.unknown;
  List<Song> _songs = [];
  List<Song> get songs => _songs;
  set songs(List<Song> value) {
    _songs = value;
    _sortedCache.clear();
    _albums = null;
    _artists = null;
  }

  // Sorting or grouping tens of thousands of songs on every rebuild would
  // make the screen stutter, so the results are kept until the library changes.
  final _sortedCache = <int, List<Song>>{};
  List<SongGroup>? _albums;
  List<SongGroup>? _artists;

  List<Song> sortedSongs(int mode) =>
      _sortedCache.putIfAbsent(mode, () => sortSongs(_songs, mode));

  List<SongGroup> get albums => _albums ??= groupByAlbum(_songs);
  List<SongGroup> get artists => _artists ??= groupByArtist(_songs);

  AudioPlayer? _player;
  final _subscriptions = <StreamSubscription<void>>[];
  int _sourceCounter = 0;

  /// Songs loaded in the player, in their original order.
  List<Song> queue = [];
  int? _index;
  bool playing = false;
  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;
  Duration duration = Duration.zero;

  /// Updated several times per second; listen to it directly rather than
  /// through [notifyListeners].
  final position = ValueNotifier(Duration.zero);

  /// Android audio session of the player, needed to attach sound effects.
  final audioSessionId = ValueNotifier<int?>(null);

  Song? get current {
    final i = _index;
    return i == null || i >= queue.length ? null : queue[i];
  }

  int? get currentIndex => _index;

  // ---- Library ----

  /// Reads the device library. With [request] false the permission dialog is
  /// never shown, so this can run silently at startup.
  Future<void> loadLibrary({bool request = true}) async {
    if (status == LibraryStatus.loading) return;
    try {
      var granted =
          await Permission.audio.isGranted ||
          await Permission.storage.isGranted ||
          await Permission.manageExternalStorage.isGranted;
      if (!granted && request) {
        final results = await [Permission.audio, Permission.storage].request();
        granted = results.values.any((s) => s.isGranted);
      }
      if (!granted) {
        if (request) {
          status = LibraryStatus.denied;
          notifyListeners();
        }
        return;
      }
      status = LibraryStatus.loading;
      notifyListeners();
      songs = (await MediaChannel.songs()).map(Song.fromMap).toList();
      status = LibraryStatus.ready;
    } on MissingPluginException {
      status = LibraryStatus.ready; // not on a device (tests)
    } on PlatformException {
      status = LibraryStatus.denied;
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugSetLibrary(List<Song> list, {int? playingIndex}) {
    songs = list;
    status = LibraryStatus.ready;
    if (playingIndex != null) {
      queue = list;
      _index = playingIndex;
      playing = true;
      duration = list[playingIndex].duration;
      position.value = duration * 0.35;
    }
    notifyListeners();
  }

  // ---- Playback ----

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = _player = AudioPlayer();
    _subscriptions.addAll([
      player.currentIndexStream.listen((i) {
        if (i == _index) return;
        _index = i;
        final song = current;
        if (song != null) settings.addRecentSong(song.id);
        notifyListeners();
      }),
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          // End of the queue: rewind and wait.
          player.pause();
          player.seek(
            Duration.zero,
            index: player.effectiveIndices.firstOrNull,
          );
        }
        final now =
            state.playing && state.processingState != ProcessingState.completed;
        if (now != playing) {
          playing = now;
          notifyListeners();
        }
      }),
      player.durationStream.listen((d) {
        duration = d ?? current?.duration ?? Duration.zero;
        notifyListeners();
      }),
      player.positionStream.listen((p) => position.value = p),
      player.androidAudioSessionIdStream.listen(
        (id) => audioSessionId.value = id,
      ),
      player.playbackEventStream.listen(
        (_) {},
        onError: (Object _) {
          // Unreadable file: move on instead of stalling.
          if (player.hasNext) player.seekToNext();
        },
      ),
    ]);
    return player;
  }

  AudioSource _source(Song s) => AudioSource.uri(
    Uri.parse(s.uri),
    tag: MediaItem(
      // Unique even when a song sits twice in the queue.
      id: '${s.id}-${_sourceCounter++}',
      title: s.title,
      artist: s.artist,
      album: s.album,
      duration: s.duration,
      // Files outside the media library (recordings) have no cover.
      artUri: s.albumId < 0
          ? null
          : Uri.parse('content://media/external/audio/albumart/${s.albumId}'),
    ),
  );

  /// Replaces the queue with [list] and starts at [index].
  Future<void> play(List<Song> list, int index, {bool? shuffled}) async {
    if (list.isEmpty) return;
    final player = _ensurePlayer();
    queue = List.of(list);
    _index = index;
    duration = list[index].duration;
    position.value = Duration.zero;
    if (shuffled != null) shuffle = shuffled;
    notifyListeners();
    try {
      await player.setShuffleModeEnabled(shuffle);
      await player.setAudioSources(
        [for (final s in queue) _source(s)],
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      settings.addRecentSong(list[index].id);
      unawaited(player.play());
    } on PlayerException {
      if (player.hasNext) unawaited(player.seekToNext());
    } on PlayerInterruptedException {
      // Another play() call took over.
    }
  }

  Future<void> shuffleAll(List<Song> list) =>
      play(list, Random().nextInt(list.length), shuffled: true);

  /// Plays the library song stored at [path]; false if it is not indexed.
  bool playPath(String path) {
    final i = songs.indexWhere((s) => s.path == path);
    if (i < 0) return false;
    play([songs[i]], 0, shuffled: false);
    return true;
  }

  void toggle() {
    final player = _player;
    if (player == null) return;
    playing ? player.pause() : player.play();
  }

  void pause() => _player?.pause();

  void next() => _player?.seekToNext();

  /// Restarts the song, or goes to the previous one when near its start.
  void previous() {
    final player = _player;
    if (player == null) return;
    if (position.value > const Duration(seconds: 3) || !player.hasPrevious) {
      player.seek(Duration.zero);
    } else {
      player.seekToPrevious();
    }
  }

  void seek(Duration to) => _player?.seek(to);

  void jumpTo(int queueIndex) {
    _player?.seek(Duration.zero, index: queueIndex);
    _player?.play();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    final player = _player;
    if (player != null) {
      if (shuffle) player.shuffle();
      player.setShuffleModeEnabled(shuffle);
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeat =
        RepeatSetting.values[(repeat.index + 1) % RepeatSetting.values.length];
    _player?.setLoopMode(
      const [LoopMode.off, LoopMode.all, LoopMode.one][repeat.index],
    );
    notifyListeners();
  }

  /// Queue positions in play order, starting with the current song.
  List<int> get upcoming {
    final player = _player;
    final i = _index;
    if (i == null) return const [];
    final order =
        player == null || player.effectiveIndices.length != queue.length
        ? [for (var k = 0; k < queue.length; k++) k]
        : player.effectiveIndices;
    final at = order.indexOf(i);
    return at < 0 ? order : order.sublist(at);
  }

  Future<void> playNext(Song song) async {
    final i = _index;
    if (_player == null || i == null) return play([song], 0);
    queue.insert(i + 1, song);
    await _player!.insertAudioSource(i + 1, _source(song));
    notifyListeners();
  }

  Future<void> addToQueue(Song song) async {
    if (_player == null || _index == null) return play([song], 0);
    queue.add(song);
    await _player!.addAudioSource(_source(song));
    notifyListeners();
  }

  Future<void> removeFromQueue(int queueIndex) async {
    final i = _index;
    if (_player == null || i == null || queueIndex == i) return;
    queue.removeAt(queueIndex);
    if (queueIndex < i) _index = i - 1;
    await _player!.removeAudioSourceAt(queueIndex);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player?.dispose();
    position.dispose();
    super.dispose();
  }
}
