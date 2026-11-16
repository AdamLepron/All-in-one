import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/pinch.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';

const _maxZoom = 5.0;
const _pageGap = 8.0;

/// Inverts page colours for night reading.
const _invert = ColorFilter.matrix(<double>[
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
]);

/// Continuous-scroll PDF viewer. Pinch or double-tap to zoom; the page is
/// rendered again at the new size so text stays sharp.
class PdfViewPage extends StatefulWidget {
  const PdfViewPage({super.key, required this.path});
  final String path;

  @override
  State<PdfViewPage> createState() => _PdfViewPageState();
}

class _PdfViewPageState extends State<PdfViewPage> {
  ({int id, int count, List<double> sizes})? _doc;
  String? _error;
  late final AppSettings _settings;

  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  double _zoom = 1;

  /// Live scale while two fingers are down.
  double _pinch = 1;
  bool _pinching = false;
  int _page = 0;
  double _viewWidth = 0;

  /// Rendered pages keyed by "page@width"; a handful is enough.
  final _renders = <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppSettings>();
    _vertical.addListener(_trackPage);
    _open();
  }

  Future<void> _open() async {
    try {
      final doc = await MediaChannel.pdfOpen(widget.path);
      if (!mounted) {
        MediaChannel.pdfClose(doc.id);
        return;
      }
      final resume = _settings.docPage(widget.path).clamp(0, doc.count - 1);
      setState(() {
        _doc = doc;
        _page = resume;
      });
      _settings.setDocPage(widget.path, resume);
      if (resume > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(resume));
      }
    } on PlatformException catch (e) {
      final protected = (e.message ?? '').toLowerCase().contains('password');
      if (mounted) {
        setState(
          () => _error = protected
              ? 'Ce PDF est protégé par un mot de passe'
              : 'Ce PDF ne peut pas être affiché',
        );
      }
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Ce PDF ne peut pas être affiché');
    }
  }

  @override
  void dispose() {
    final doc = _doc;
    if (doc != null) {
      _settings.setDocPage(widget.path, _page, notify: false);
      MediaChannel.pdfClose(doc.id);
    }
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  double _pageHeight(int i, double width) {
    final sizes = _doc!.sizes;
    return width * sizes[i * 2 + 1] / sizes[i * 2];
  }

  /// Scroll offset of the top of page [i] at the current zoom.
  double _offsetOf(int i) {
    final width = _viewWidth * _zoom;
    var offset = 0.0;
    for (var k = 0; k < i; k++) {
      offset += _pageHeight(k, width) + _pageGap;
    }
    return offset;
  }

  void _trackPage() {
    final doc = _doc;
    if (doc == null || _viewWidth == 0 || !_vertical.hasClients) return;
    final width = _viewWidth * _zoom;
    // The current page is the one crossing the middle of the screen.
    final middle = _vertical.offset + _vertical.position.viewportDimension / 2;
    var offset = 0.0;
    var page = doc.count - 1;
    for (var i = 0; i < doc.count; i++) {
      offset += _pageHeight(i, width) + _pageGap;
      if (offset > middle) {
        page = i;
        break;
      }
    }
    if (page != _page) setState(() => _page = page);
  }

  void _jumpTo(int page) {
    if (!_vertical.hasClients) return;
    _vertical.jumpTo(
      _offsetOf(page).clamp(0.0, _vertical.position.maxScrollExtent),
    );
  }

  /// Changes the zoom while keeping the same content under the screen centre.
  void _setZoom(double target) {
    final zoom = target.clamp(1.0, _maxZoom);
    if (zoom == _zoom || !_vertical.hasClients) {
      setState(() => _pinch = 1);
      return;
    }
    final ratio = zoom / _zoom;
    final view = _vertical.position.viewportDimension;
    final newVertical = (_vertical.offset + view / 2) * ratio - view / 2;
    final newHorizontal = _horizontal.hasClients
        ? (_horizontal.offset + _viewWidth / 2) * ratio - _viewWidth / 2
        : (_viewWidth * zoom - _viewWidth) / 2;
    setState(() {
      _zoom = zoom;
      _pinch = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vertical.hasClients) {
        _vertical.jumpTo(
          newVertical.clamp(0.0, _vertical.position.maxScrollExtent),
        );
      }
      if (_horizontal.hasClients) {
        _horizontal.jumpTo(
          newHorizontal.clamp(0.0, _horizontal.position.maxScrollExtent),
        );
      }
    });
  }

  Future<Uint8List?> _render(int page, int pixelWidth) {
    final key = '$page@$pixelWidth';
    final hit = _renders.remove(key);
    if (hit != null) return _renders[key] = hit;
    if (_renders.length >= 8) _renders.remove(_renders.keys.first);
    return _renders[key] = MediaChannel.pdfRender(
      _doc!.id,
      page,
      pixelWidth,
    ).then<Uint8List?>((v) => v).catchError((Object _) => null);
  }

  Future<void> _askPage() async {
    final doc = _doc!;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Aller à la page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '1 – ${doc.count}'),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Aller'),
          ),
        ],
      ),
    );
    final page = int.tryParse(value ?? '');
    if (page != null) _jumpTo((page - 1).clamp(0, doc.count - 1));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final night = settings.readerNight;
    final doc = _doc;
    return Scaffold(
      backgroundColor: night ? Colors.black : const Color(0xFFE9E9EE),
      appBar: AppBar(
        title: Text(
          p.basename(widget.path),
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: night ? 'Mode jour' : 'Mode nuit',
            icon: Icon(
              night ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: () => settings.readerNight = !night,
          ),
          IconButton(
            tooltip: 'Partager',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(widget.path)]),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(_error!),
                ],
              ),
            )
          : doc == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, box) {
                _viewWidth = box.maxWidth;
                final width = _viewWidth * _zoom;
                final ratio = MediaQuery.devicePixelRatioOf(context);
                final pixelWidth = (width * ratio).round().clamp(64, 4096);
                return Stack(
                  children: [
                    PinchDetector(
                      onStart: () => setState(() => _pinching = true),
                      onUpdate: (s) => setState(
                        () => _pinch = (s * _zoom).clamp(1.0, _maxZoom) / _zoom,
                      ),
                      onEnd: (s) {
                        _pinching = false;
                        _setZoom(_zoom * s);
                      },
                      child: GestureDetector(
                        onDoubleTap: () => _setZoom(_zoom > 1.05 ? 1 : 2),
                        child: Transform.scale(
                          scale: _pinch,
                          child: SingleChildScrollView(
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            physics: _pinching || _zoom <= 1
                                ? const NeverScrollableScrollPhysics()
                                : const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: width,
                              child: ListView.builder(
                                controller: _vertical,
                                physics: _pinching
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: doc.count,
                                itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: _pageGap,
                                  ),
                                  child: SizedBox(
                                    height: _pageHeight(i, width),
                                    child: _PdfPage(
                                      // A new zoom level builds a new image.
                                      key: ValueKey('$i@$pixelWidth'),
                                      bytes: _render(i, pixelWidth),
                                      night: night,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _askPage,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                '${_page + 1} / ${doc.count}${_zoom > 1.05 ? '  ·  ${(_zoom * 100).round()} %' : ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
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
}

class _PdfPage extends StatelessWidget {
  const _PdfPage({super.key, required this.bytes, required this.night});
  final Future<Uint8List?> bytes;
  final bool night;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: night ? Colors.black : Colors.white,
      child: FutureBuilder<Uint8List?>(
        future: bytes,
        builder: (_, snap) {
          if (snap.data == null) {
            return snap.connectionState == ConnectionState.done
                ? const Center(child: Icon(Icons.broken_image_outlined))
                : const SizedBox.shrink();
          }
          final image = Image.memory(
            snap.data!,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
          return night
              ? ColorFiltered(colorFilter: _invert, child: image)
              : image;
        },
      ),
    );
  }
}
