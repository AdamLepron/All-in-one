import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'media_library.dart';
import 'viewer_page.dart';

/// Square thumbnail of a photo or video.
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.media, {super.key, this.showDuration = true});
  final Media media;
  final bool showDuration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surfaceContainerHighest),
        FutureBuilder<Uint8List?>(
          future: ThumbnailCache.get(media),
          builder: (_, snap) => snap.data == null
              ? Icon(
                  media.video ? Icons.movie_outlined : Icons.image_outlined,
                  color: scheme.outline,
                )
              : Image.memory(
                  snap.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
        if (media.video && showDuration)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  Text(
                    formatDuration(media.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Holds the multi-selection of a grid so the app bar can act on it.
class MediaSelection extends ChangeNotifier {
  final keys = <String>{};

  bool get active => keys.isNotEmpty;

  void toggle(Media m) {
    if (!keys.remove(m.key)) keys.add(m.key);
    notifyListeners();
  }

  void clear() {
    keys.clear();
    notifyListeners();
  }
}

/// Timeline grid grouped by day with sticky date headers. Pinch to change
/// the number of columns.
class MediaGrid extends StatefulWidget {
  const MediaGrid({super.key, required this.items, required this.selection});
  final List<Media> items;
  final MediaSelection selection;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final columns = settings.galleryColumns;
    final scheme = Theme.of(context).colorScheme;

    // Consecutive items of the same day form one group.
    final groups = <(String, List<int>)>[];
    for (var i = 0; i < widget.items.length; i++) {
      final label = dayLabel(widget.items[i].date);
      if (groups.isEmpty || groups.last.$1 != label) groups.add((label, []));
      groups.last.$2.add(i);
    }

    return GestureDetector(
      onScaleStart: (_) => _scale = 1,
      onScaleUpdate: (d) => _scale = d.scale,
      onScaleEnd: (_) {
        if (_scale > 1.25 && columns > 2) settings.galleryColumns = columns - 1;
        if (_scale < 0.8 && columns < 7) settings.galleryColumns = columns + 1;
      },
      child: ListenableBuilder(
        listenable: widget.selection,
        builder: (context, _) => Scrollbar(
          interactive: true,
          thickness: 6,
          radius: const Radius.circular(3),
          child: CustomScrollView(
            slivers: [
              for (final (label, indexes) in groups)
                SliverMainAxisGroup(
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _DayHeader(
                        label,
                        scheme.surface,
                        scheme.onSurface,
                      ),
                    ),
                    SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: indexes.length,
                      itemBuilder: (_, i) => _cell(context, indexes[i]),
                    ),
                  ],
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int index) {
    final media = widget.items[index];
    final selection = widget.selection;
    final selected = selection.keys.contains(media.key);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        if (selection.active) {
          selection.toggle(media);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ViewerPage(items: widget.items, initialIndex: index),
            ),
          );
        }
      },
      onLongPress: () {
        HapticFeedback.selectionClick();
        selection.toggle(media);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(selected ? 8 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(selected ? 8 : 0),
              child: MediaThumb(media),
            ),
          ),
          if (selection.active)
            Positioned(
              left: 4,
              top: 4,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: selected ? scheme.primary : Colors.white,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader(this.label, this.background, this.foreground);
  final String label;
  final Color background;
  final Color foreground;

  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background.withValues(alpha: 0.94),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeader old) =>
      old.label != label || old.background != background;
}

Future<void> shareMedia(List<Media> items) => SharePlus.instance.share(
  ShareParams(files: [for (final m in items) XFile(m.path)]),
);

/// Moves [items] to the recycle bin and offers to undo.
Future<bool> trashMedia(BuildContext context, List<Media> items) async {
  if (!await ensureFullFileAccess(context)) return false;
  if (!context.mounted) return false;
  final library = context.read<MediaLibrary>();
  final trash = Trash.device();
  final done = <Media>[];
  final trashed = <TrashItem>[];
  for (final m in items) {
    try {
      trashed.add(await trash.put(m.path));
      done.add(m);
    } on Exception {
      continue; // read-only location: leave the item in place
    }
  }
  library.forget(done);
  if (!context.mounted) return done.isNotEmpty;
  if (done.isEmpty) {
    showMessage(context, 'Suppression impossible pour cet emplacement');
    return false;
  }
  showMessage(
    context,
    done.length == 1
        ? 'Élément déplacé dans la corbeille'
        : '${done.length} éléments déplacés dans la corbeille',
    action: SnackBarAction(
      label: 'Annuler',
      onPressed: () async {
        final restored = <String>[];
        for (final item in trashed) {
          restored.add(await trash.restore(item));
        }
        await MediaChannel.rescan(restored);
        await library.load(request: false);
      },
    ),
  );
  return true;
}
