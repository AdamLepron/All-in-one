import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/pinch.dart';
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
/// One line of the timeline: a day heading, or a row of thumbnails.
class TimelineLine {
  const TimelineLine.header(this.label) : start = 0, end = 0;
  const TimelineLine.cells(this.label, this.start, this.end);

  /// Day label, also used for the heading that stays at the top.
  final String label;

  /// Range [start, end) of the items shown on a row.
  final int start;
  final int end;

  bool get isHeader => start == end;
}

const _gap = 2.0;
const _headerHeight = 44.0;

/// Splits [items] (newest first) into heading and thumbnail lines for
/// [columns] columns. Computed once per change, not per frame.
@visibleForTesting
List<TimelineLine> buildTimeline(List<Media> items, int columns) {
  final lines = <TimelineLine>[];
  var i = 0;
  while (i < items.length) {
    final label = dayLabel(items[i].date);
    var end = i;
    while (end < items.length && dayLabel(items[end].date) == label) {
      end++;
    }
    lines.add(TimelineLine.header(label));
    for (var row = i; row < end; row += columns) {
      lines.add(
        TimelineLine.cells(
          label,
          row,
          row + columns < end ? row + columns : end,
        ),
      );
    }
    i = end;
  }
  return lines;
}

/// Timeline grouped by day, with the current day's heading kept at the top.
/// Pinch to change the number of columns.
///
/// It is one flat list with known line heights rather than one scrollable
/// section per day: with tens of thousands of photos, laying out a thousand
/// sections on every frame made scrolling stutter.
class MediaGrid extends StatefulWidget {
  const MediaGrid({super.key, required this.items, required this.selection});
  final List<Media> items;
  final MediaSelection selection;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  final _controller = ScrollController();
  final _sticky = ValueNotifier<String>('');

  List<TimelineLine> _lines = const [];
  List<Media>? _linesFor;
  int _linesColumns = 0;

  /// Start offset of each line, plus the total at the end.
  List<double> _offsets = const [0];
  double _offsetsWidth = -1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateSticky);
  }

  @override
  void dispose() {
    _controller.dispose();
    _sticky.dispose();
    super.dispose();
  }

  double _extent(int line, double cell) =>
      _lines[line].isHeader ? _headerHeight : cell + _gap;

  void _updateSticky() {
    if (_lines.isEmpty) return;
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    // Last line starting at or before the offset.
    var low = 0;
    var high = _lines.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final label = _lines[low].label;
    if (_sticky.value != label) _sticky.value = label;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final columns = settings.galleryColumns;
    final scheme = Theme.of(context).colorScheme;

    if (!identical(_linesFor, widget.items) || _linesColumns != columns) {
      _lines = buildTimeline(widget.items, columns);
      _linesFor = widget.items;
      _linesColumns = columns;
      _offsetsWidth = -1;
    }

    return PinchDetector(
      onEnd: (scale) {
        if (scale > 1.25 && columns > 2) settings.galleryColumns = columns - 1;
        if (scale < 0.8 && columns < 7) settings.galleryColumns = columns + 1;
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final cell = (box.maxWidth - (columns - 1) * _gap) / columns;
          if (_offsetsWidth != box.maxWidth) {
            var sum = 0.0;
            _offsets = [
              for (var i = 0; i < _lines.length; i++)
                () {
                  final start = sum;
                  sum += _extent(i, cell);
                  return start;
                }(),
              sum,
            ];
            _offsetsWidth = box.maxWidth;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _updateSticky(),
            );
          }
          return Stack(
            children: [
              ListenableBuilder(
                listenable: widget.selection,
                builder: (context, _) => Scrollbar(
                  controller: _controller,
                  interactive: true,
                  thickness: 6,
                  radius: const Radius.circular(3),
                  child: CustomScrollView(
                    controller: _controller,
                    slivers: [
                      SliverVariedExtentList.builder(
                        itemCount: _lines.length,
                        itemExtentBuilder: (i, _) => _extent(i, cell),
                        itemBuilder: (context, i) =>
                            _line(context, _lines[i], cell),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: ValueListenableBuilder<String>(
                    valueListenable: _sticky,
                    builder: (_, label, _) => Container(
                      height: _headerHeight,
                      color: scheme.surface.withValues(alpha: 0.94),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _line(BuildContext context, TimelineLine line, double cell) {
    if (line.isHeader) {
      // The heading kept at the top covers this one when they meet.
      return Container(
        height: _headerHeight,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          line.label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Row(
        children: [
          for (var i = line.start; i < line.end; i++) ...[
            if (i > line.start) const SizedBox(width: _gap),
            SizedBox(width: cell, height: cell, child: _cell(context, i)),
          ],
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int index) {
    final media = widget.items[index];
    final selection = widget.selection;
    final selected = selection.keys.contains(media.key);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${media.video ? 'Vidéo' : 'Photo'} du ${dayLabel(media.date).toLowerCase()}${media.video ? ', ${formatDuration(media.duration)}' : ''}',
      button: true,
      image: true,
      selected: selected,
      excludeSemantics: true,
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
      onLongPress: () => selection.toggle(media),
      child: GestureDetector(
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
      ),
    );
  }
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
