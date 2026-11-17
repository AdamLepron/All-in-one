import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../photo/photo_editor_page.dart';
import '../video/video_player_page.dart';
import 'media_grid.dart';
import 'media_library.dart';

/// Full-screen viewer: swipe between items, pinch or double-tap to zoom,
/// tap to hide the controls.
class ViewerPage extends StatefulWidget {
  const ViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });
  final List<Media> items;
  final int initialIndex;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late final List<Media> _items = List.of(widget.items);
  late int _index = widget.initialIndex;
  late final _pages = PageController(initialPage: widget.initialIndex);
  bool _chrome = true;
  bool _zoomed = false;

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(
      _chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _delete() async {
    final media = _items[_index];
    if (!await trashMedia(context, [media]) || !mounted) return;
    if (_items.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _items.removeAt(_index);
      _index = _index.clamp(0, _items.length - 1);
    });
  }

  void _info() {
    final m = _items[_index];
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(fullDate(m.date)),
            ),
            ListTile(
              leading: Icon(
                m.video ? Icons.movie_outlined : Icons.image_outlined,
              ),
              title: Text(m.name),
              subtitle: Text(
                [
                  if (m.width > 0) '${m.width} × ${m.height}',
                  formatBytes(m.size),
                  if (m.video) formatDuration(m.duration),
                ].join(' · '),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(m.album),
              subtitle: Text(m.path),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final media = _items[_index];
    final favorite = settings.isFavoriteMedia(media.key);
    const white = Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            // While zoomed, horizontal drags pan the photo instead.
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (_, i) {
              final m = _items[i];
              return m.video
                  ? _VideoPreview(media: m, onTap: _toggleChrome)
                  : _ZoomablePhoto(
                      key: ValueKey(m.key),
                      media: m,
                      onTap: _toggleChrome,
                      onZoomChanged: (z) {
                        if (z != _zoomed) setState(() => _zoomed = z);
                      },
                    );
            },
          ),
          if (_chrome) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 24),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Retour',
                          icon: const Icon(Icons.arrow_back),
                          color: white,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dayLabel(media.date),
                                style: const TextStyle(
                                  color: white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${media.date.hour.toString().padLeft(2, '0')}:${media.date.minute.toString().padLeft(2, '0')} · ${_index + 1}/${_items.length}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Action(
                          icon: favorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          label: 'Favori',
                          color: favorite ? const Color(0xFFFF5C7A) : white,
                          onTap: () => settings.toggleFavoriteMedia(media.key),
                        ),
                        if (!media.video)
                          _Action(
                            icon: Icons.tune_rounded,
                            label: 'Modifier',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    PhotoEditorPage(path: media.path),
                              ),
                            ),
                          ),
                        _Action(
                          icon: Icons.share_outlined,
                          label: 'Partager',
                          onTap: () => shareMedia([media]),
                        ),
                        _Action(
                          icon: Icons.info_outline,
                          label: 'Détails',
                          onTap: _info,
                        ),
                        _Action(
                          icon: Icons.delete_outline,
                          label: 'Supprimer',
                          onTap: _delete,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.media,
    required this.onTap,
    required this.onZoomChanged,
  });
  final Media media;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(
      () => widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
    );
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
    } else {
      // Zoom 2.5× around the tapped point.
      const scale = 2.5;
      _transform.value = Matrix4.identity()
        ..translateByDouble(
          -_doubleTapAt.dx * (scale - 1),
          -_doubleTapAt.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context);
    // Decode at twice the screen width: sharp when zoomed, light on memory.
    final decodeWidth = (view.size.width * view.devicePixelRatio * 2).round();
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: SizedBox.expand(
          child: Image.file(
            File(widget.media.path),
            fit: BoxFit.contain,
            cacheWidth: decodeWidth,
            gaplessPlayback: true,
            // The grid thumbnail shows until the full image is decoded.
            frameBuilder: (_, child, frame, _) =>
                frame == null ? _Placeholder(widget.media) : child,
            errorBuilder: (_, _, _) => _Placeholder(widget.media, failed: true),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.media, {this.failed = false});
  final Media media;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: ThumbnailCache.get(media),
      builder: (_, snap) => snap.data != null
          ? Image.memory(snap.data!, fit: BoxFit.contain, gaplessPlayback: true)
          : Center(
              child: failed
                  ? const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    )
                  : const SizedBox.shrink(),
            ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.media, required this.onTap});
  final Media media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Placeholder(media),
          Center(
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VideoPlayerPage(media: media),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
