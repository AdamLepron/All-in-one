import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../equalizer/equalizer_page.dart';
import 'artwork.dart';
import 'music_controller.dart';
import 'song.dart';

/// Opens the full-screen player; drag down to close it.
void showNowPlaying(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 1, child: NowPlaying()),
  );
}

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  int? _tintedAlbum;
  Color? _tint;
  double? _dragValue;

  /// Tints the background with the dominant colour of the cover.
  Future<void> _updateTint(Song song) async {
    if (_tintedAlbum == song.albumId) return;
    _tintedAlbum = song.albumId;
    final Uint8List? bytes = await ArtworkCache.get(song);
    Color? tint;
    if (bytes != null) {
      try {
        final scheme = await ColorScheme.fromImageProvider(
          provider: MemoryImage(bytes),
          brightness: Brightness.dark,
        );
        tint = scheme.primaryContainer;
      } catch (_) {
        tint = null; // undecodable cover: keep the default colour
      }
    }
    if (mounted && _tintedAlbum == song.albumId) setState(() => _tint = tint);
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final settings = context.watch<AppSettings>();
    final song = music.current;
    if (song == null) return const SizedBox.shrink();
    _updateTint(song);

    final base =
        _tint ??
        ColorScheme.fromSeed(
          seedColor: Theme.of(context).colorScheme.primary,
          brightness: Brightness.dark,
        ).primaryContainer;
    const white = Colors.white;
    final dim = white.withValues(alpha: 0.7);
    final favorite = settings.isFavorite(song.id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base, Color.lerp(base, Colors.black, 0.85)!],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Réduire',
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 32,
                    ),
                    color: white,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'LECTURE EN COURS',
                          style: TextStyle(
                            color: dim,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          song.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Égaliseur',
                    icon: const Icon(Icons.equalizer_rounded),
                    color: white,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EqualizerPage(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "File d'attente",
                    icon: const Icon(Icons.queue_music_rounded),
                    color: white,
                    onPressed: () => _showQueue(context),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -200) music.next();
                      if (v > 200) music.previous();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 32,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Artwork(song, radius: 12, large: true),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: dim, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: favorite
                        ? 'Retirer des favoris'
                        : 'Ajouter aux favoris',
                    icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 28,
                    ),
                    color: favorite ? const Color(0xFF1ED760) : white,
                    onPressed: () => settings.toggleFavorite(song.id),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<Duration>(
                valueListenable: music.position,
                builder: (_, position, _) {
                  final total = music.duration.inMilliseconds.toDouble();
                  final value =
                      (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
                        0.0,
                        total,
                      );
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: white,
                          inactiveTrackColor: white.withValues(alpha: 0.25),
                          thumbColor: white,
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          max: total <= 0 ? 1 : total,
                          value: total <= 0 ? 0 : value,
                          onChanged: (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            music.seek(Duration(milliseconds: v.round()));
                            setState(() => _dragValue = null);
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(
                              Duration(milliseconds: value.round()),
                            ),
                            style: TextStyle(color: dim, fontSize: 12),
                          ),
                          Text(
                            formatDuration(music.duration),
                            style: TextStyle(color: dim, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Aléatoire',
                    icon: const Icon(Icons.shuffle_rounded),
                    color: music.shuffle ? const Color(0xFF1ED760) : white,
                    onPressed: music.toggleShuffle,
                  ),
                  IconButton(
                    tooltip: 'Précédent',
                    icon: const Icon(Icons.skip_previous_rounded, size: 44),
                    color: white,
                    onPressed: music.previous,
                  ),
                  Material(
                    color: white,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: music.toggle,
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: Icon(
                          music.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 40,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Suivant',
                    icon: const Icon(Icons.skip_next_rounded, size: 44),
                    color: white,
                    onPressed: music.next,
                  ),
                  IconButton(
                    tooltip: 'Répétition',
                    icon: Icon(
                      music.repeat == RepeatSetting.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                    ),
                    color: music.repeat == RepeatSetting.off
                        ? white
                        : const Color(0xFF1ED760),
                    onPressed: music.cycleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) {
          final music = context.watch<MusicController>();
          final order = music.upcoming;
          final scheme = Theme.of(context).colorScheme;
          return ListView.builder(
            controller: scroll,
            itemCount: order.length + 1,
            itemBuilder: (_, row) {
              if (row == 0) {
                return ListTile(
                  title: Text(
                    "File d'attente",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  subtitle: Text(
                    '${order.length} titre${order.length > 1 ? 's' : ''}${music.shuffle ? ' · aléatoire' : ''}',
                  ),
                );
              }
              final index = order[row - 1];
              final song = music.queue[index];
              final isCurrent = index == music.currentIndex;
              final tile = ListTile(
                leading: Artwork(song, size: 44),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.w800 : null,
                    color: isCurrent ? scheme.primary : null,
                  ),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isCurrent
                    ? Icon(Icons.graphic_eq_rounded, color: scheme.primary)
                    : null,
                onTap: isCurrent ? null : () => music.jumpTo(index),
              );
              if (isCurrent) return tile;
              return Dismissible(
                key: ObjectKey(song),
                background: ColoredBox(color: scheme.errorContainer),
                onDismissed: (_) => music.removeFromQueue(index),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }
}
