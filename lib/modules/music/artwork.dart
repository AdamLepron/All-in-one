import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/platform.dart';
import 'song.dart';

/// In-memory cache of cover art, one entry per album and size.
class ArtworkCache {
  static final _cache = <String, Future<Uint8List?>>{};
  static const _capacity = 400;

  static Future<Uint8List?> get(Song song, {bool large = false}) {
    final key = '${song.albumId}-$large';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // move to most recent
    if (_cache.length >= _capacity) _cache.remove(_cache.keys.first);
    return _cache[key] = MediaChannel.artwork(
      song.id,
      song.albumId,
      large ? 900 : 256,
    ).then<Uint8List?>((v) => v).catchError((Object _) => null);
  }
}

/// Square cover art with a tinted placeholder.
class Artwork extends StatelessWidget {
  const Artwork(
    this.song, {
    super.key,
    this.size,
    this.radius = 6,
    this.large = false,
  });
  final Song? song;
  final double? size;
  final double radius;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (_, box) => Icon(
          Icons.music_note_rounded,
          size: box.biggest.shortestSide * 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final s = song;
    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: s == null
              ? placeholder
              : FutureBuilder<Uint8List?>(
                  future: ArtworkCache.get(s, large: large),
                  builder: (_, snap) => snap.data == null
                      ? placeholder
                      : Image.memory(
                          snap.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
        ),
      ),
    );
  }
}
