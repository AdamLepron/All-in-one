import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'artwork.dart';
import 'music_controller.dart';
import 'now_playing.dart';

/// Compact player shown above the navigation bar while a queue is loaded.
/// Tap to expand, swipe sideways to change track.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final song = music.current;
    if (song == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showNowPlaying(context),
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) music.next();
              if (v > 200) music.previous();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                  child: Row(
                    children: [
                      Artwork(song, size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSecondaryContainer.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: music.playing ? 'Pause' : 'Lecture',
                        icon: Icon(
                          music.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 30,
                        ),
                        color: scheme.onSecondaryContainer,
                        onPressed: music.toggle,
                      ),
                      IconButton(
                        tooltip: 'Suivant',
                        icon: const Icon(Icons.skip_next_rounded, size: 28),
                        color: scheme.onSecondaryContainer,
                        onPressed: music.next,
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: music.position,
                  builder: (_, position, _) => LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    value: music.duration.inMilliseconds == 0
                        ? 0
                        : (position.inMilliseconds /
                                  music.duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
