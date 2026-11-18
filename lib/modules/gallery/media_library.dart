import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/platform.dart';

/// A photo or a video stored on the device.
class Media {
  const Media({
    required this.id,
    required this.video,
    required this.path,
    required this.name,
    required this.date,
    required this.uri,
    this.size = 0,
    this.width = 0,
    this.height = 0,
    this.album = '',
    this.duration = Duration.zero,
  });

  final int id;
  final bool video;
  final String path;
  final String name;
  final DateTime date;
  final String uri;
  final int size;
  final int width;
  final int height;
  final String album;
  final Duration duration;

  /// Unique across photos and videos, whose ids overlap.
  String get key => '${video ? 'v' : 'i'}$id';

  static Media fromMap(Map<Object?, Object?> m) => Media(
    id: (m['id'] as num).toInt(),
    video: m['video'] == true,
    path: (m['path'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    date: DateTime.fromMillisecondsSinceEpoch(
      (m['date'] as num?)?.toInt() ?? 0,
    ),
    uri: m['uri'] as String,
    size: (m['size'] as num?)?.toInt() ?? 0,
    width: (m['width'] as num?)?.toInt() ?? 0,
    height: (m['height'] as num?)?.toInt() ?? 0,
    album: (m['album'] as String?) ?? 'Autres',
    duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
  );
}

class MediaAlbum {
  MediaAlbum(this.name, this.items);
  final String name;

  /// Most recent first.
  final List<Media> items;
}

enum MediaStatus { unknown, loading, denied, ready }

/// Photos and videos of the device, most recent first.
class MediaLibrary extends ChangeNotifier {
  MediaStatus status = MediaStatus.unknown;
  List<Media> _items = [];
  List<Media> get items => _items;
  set items(List<Media> value) {
    _items = value;
    _videos = null;
    _albums = null;
  }

  List<Media>? _videos;
  List<MediaAlbum>? _albums;

  List<Media> get videos => _videos ??= _items.where((m) => m.video).toList();

  /// Albums ordered by their most recent item.
  List<MediaAlbum> get albums => _albums ??= _buildAlbums();

  List<MediaAlbum> _buildAlbums() {
    final map = <String, List<Media>>{};
    for (final m in items) {
      map.putIfAbsent(m.album, () => []).add(m);
    }
    return [for (final e in map.entries) MediaAlbum(e.key, e.value)]
      ..sort((a, b) => b.items.first.date.compareTo(a.items.first.date));
  }

  Media? byKey(String key) {
    for (final m in items) {
      if (m.key == key) return m;
    }
    return null;
  }

  /// With [request] false the permission dialog is never shown.
  Future<void> load({bool request = true}) async {
    if (status == MediaStatus.loading) return;
    try {
      Future<bool> allowed(Permission p) async {
        final s = await p.status;
        return s.isGranted || s.isLimited;
      }

      var granted =
          await allowed(Permission.photos) ||
          await allowed(Permission.videos) ||
          await allowed(Permission.storage) ||
          await allowed(Permission.manageExternalStorage);
      if (!granted && request) {
        final results = await [
          Permission.photos,
          Permission.videos,
          Permission.storage,
        ].request();
        granted = results.values.any((s) => s.isGranted || s.isLimited);
      }
      if (!granted) {
        if (request) {
          status = MediaStatus.denied;
          notifyListeners();
        }
        return;
      }
      if (items.isEmpty) {
        status = MediaStatus.loading;
        notifyListeners();
      }
      items = (await MediaChannel.media()).map(Media.fromMap).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      status = MediaStatus.ready;
    } on MissingPluginException {
      status = MediaStatus.ready; // not on a device (tests)
    } on PlatformException {
      status = MediaStatus.denied;
    }
    notifyListeners();
  }

  /// Drops [removed] from the list after they were deleted on disk.
  void forget(Iterable<Media> removed) {
    final keys = {for (final m in removed) m.key};
    items = items.where((m) => !keys.contains(m.key)).toList();
    MediaChannel.scan([for (final m in removed) m.path]);
    notifyListeners();
  }

  @visibleForTesting
  void debugSet(List<Media> list) {
    items = list..sort((a, b) => b.date.compareTo(a.date));
    status = MediaStatus.ready;
    notifyListeners();
  }
}

/// In-memory cache of grid thumbnails.
class ThumbnailCache {
  static final _cache = <String, Future<Uint8List?>>{};
  static const _capacity = 800;

  static Future<Uint8List?> get(Media media) {
    final hit = _cache.remove(media.key);
    if (hit != null) return _cache[media.key] = hit; // move to most recent
    if (_cache.length >= _capacity) _cache.remove(_cache.keys.first);
    return _cache[media.key] = MediaChannel.thumbnail(
      media.id,
      video: media.video,
    ).then<Uint8List?>((v) => v).catchError((Object _) => null);
  }
}
