import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/pinch.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';
import 'annotations.dart';

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
  const PdfViewPage({super.key, required this.path, this.annotations});
  final String path;

  /// Where annotations are kept; the app's own folder when null.
  final AnnotationStore? annotations;

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

  // Search.
  bool _searching = false;
  final _query = TextEditingController();
  List<PdfHit> _hits = const [];
  int _hit = -1;
  bool _searchBusy = false;
  String? _searchNote;

  // Table of contents, read on demand.
  List<({String title, int page, int level})>? _outline;

  // Annotations.
  late final AnnotationStore _annotationStore =
      widget.annotations ?? AnnotationStore();
  List<Annotation> _annots = [];
  _Tool _tool = _Tool.none;
  bool _annotating = false;
  int _colorIndex = 0;
  final _live = ValueNotifier<_Live?>(null);

  bool get _drawing =>
      _annotating && (_tool == _Tool.highlight || _tool == _Tool.pen);

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppSettings>();
    _vertical.addListener(_trackPage);
    _annotationStore.load(widget.path).then((list) {
      if (mounted) setState(() => _annots = list);
    });
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
    _query.dispose();
    _live.dispose();
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

  // ---- Search ----

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() {
      _searchBusy = true;
      _searchNote = null;
    });
    final hits = await MediaChannel.pdfSearch(widget.path, q);
    if (!mounted) return;
    setState(() {
      _searchBusy = false;
      _hits = hits ?? const [];
      _hit = _hits.isEmpty ? -1 : 0;
      _searchNote = hits == null
          ? 'Recherche impossible dans ce PDF'
          : hits.isEmpty
          ? 'Aucun résultat'
          : null;
    });
    if (_hit >= 0) _showHit(_hit);
  }

  void _showHit(int i) {
    if (i < 0 || i >= _hits.length || _doc == null) return;
    setState(() => _hit = i);
    final hit = _hits[i];
    if (!_vertical.hasClients || _viewWidth == 0) return;
    final width = _viewWidth * _zoom;
    final top = hit.rects.first[1] * _pageHeight(hit.page, width);
    final view = _vertical.position.viewportDimension;
    _vertical.animateTo(
      (_offsetOf(hit.page) + top - view * 0.3).clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _stopSearch() => setState(() {
    _searching = false;
    _hits = const [];
    _hit = -1;
    _searchNote = null;
    _query.clear();
  });

  void _showResults() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scroll) => ListView.builder(
          controller: scroll,
          itemCount: _hits.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return ListTile(
                title: Text(
                  '${_hits.length} résultat${_hits.length > 1 ? 's' : ''}'
                  '${_hits.length >= 500 ? ' (limité)' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            }
            final hit = _hits[i - 1];
            return ListTile(
              dense: true,
              selected: i - 1 == _hit,
              title: Text(
                hit.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text('p. ${hit.page + 1}'),
              onTap: () {
                Navigator.pop(sheet);
                _showHit(i - 1);
              },
            );
          },
        ),
      ),
    );
  }

  // ---- Table of contents ----

  Future<void> _showOutline() async {
    _outline ??= await MediaChannel.pdfOutline(widget.path);
    if (!mounted) return;
    final items = _outline!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => items.isEmpty
            ? const Center(child: Text("Ce PDF n'a pas de sommaire"))
            : ListView.builder(
                controller: scroll,
                itemCount: items.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return ListTile(
                      title: Text(
                        'Sommaire',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    );
                  }
                  final it = items[i - 1];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(
                      left: 16.0 + it.level * 18,
                      right: 16,
                    ),
                    title: Text(
                      it.title.isEmpty ? '(sans titre)' : it.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: it.page < 0 ? null : Text('${it.page + 1}'),
                    enabled: it.page >= 0,
                    onTap: () {
                      Navigator.pop(sheet);
                      _jumpTo(it.page.clamp(0, _doc!.count - 1));
                    },
                  );
                },
              ),
      ),
    );
  }

  // ---- Annotations ----

  static const _palette = [
    Color(0xFFFFD60A),
    Color(0xFF30D158),
    Color(0xFFFF6482),
    Color(0xFF0A84FF),
  ];
  static const _paletteNames = ['jaune', 'vert', 'rose', 'bleu'];

  void _saveAnnotations() => _annotationStore.save(widget.path, _annots);

  void _addAnnotation(Annotation a) {
    setState(() => _annots = [..._annots, a]);
    _saveAnnotations();
  }

  void _removeAnnotation(Annotation a) {
    setState(() => _annots = [..._annots.where((x) => x != a)]);
    _saveAnnotations();
  }

  Future<void> _editNote(Annotation note) async {
    final controller = TextEditingController(text: note.text);
    final result = await showDialog<String?>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, ''),
            child: const Text('Supprimer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      _removeAnnotation(note);
    } else {
      setState(() => note.text = result);
      _saveAnnotations();
    }
  }

  Future<void> _newNote(int page, Offset at) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Nouvelle note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    _addAnnotation(
      Annotation(
        kind: AnnotationKind.note,
        page: page,
        color: _palette[_colorIndex].toARGB32(),
        points: [at],
        text: text,
      ),
    );
  }

  void _undoAnnotation() {
    if (_annots.isEmpty) return;
    setState(() => _annots = _annots.sublist(0, _annots.length - 1));
    _saveAnnotations();
  }

  void _onOverlayTap(int page, Offset at) {
    if (_tool == _Tool.eraser) {
      final hit = _annots.lastWhere(
        (a) => a.page == page && a.hits(at, 0.012),
        orElse: () => Annotation(kind: AnnotationKind.note, page: -1, color: 0),
      );
      if (hit.page >= 0) _removeAnnotation(hit);
    } else if (_tool == _Tool.note) {
      _newNote(page, at);
    }
  }

  void _onOverlayDrag(int page, Offset at, {required bool start}) {
    final live = _live.value;
    if (_tool == _Tool.highlight) {
      _live.value = start || live == null
          ? _Live(page, start: at, end: at)
          : _Live(page, start: live.start, end: at);
    } else if (_tool == _Tool.pen) {
      _live.value = start || live == null
          ? _Live(page, stroke: [at])
          : _Live(page, stroke: [...live.stroke, at]);
    }
  }

  void _onOverlayDragEnd() {
    final live = _live.value;
    _live.value = null;
    if (live == null) return;
    final color = _palette[_colorIndex].toARGB32();
    if (_tool == _Tool.highlight && live.start != null) {
      final r = Rect.fromPoints(live.start!, live.end!);
      if (r.width > 0.01 && r.height > 0.004) {
        _addAnnotation(
          Annotation(
            kind: AnnotationKind.highlight,
            page: live.page,
            color: color,
            rects: [r],
          ),
        );
      }
    } else if (_tool == _Tool.pen && live.stroke.length > 1) {
      _addAnnotation(
        Annotation(
          kind: AnnotationKind.ink,
          page: live.page,
          color: color,
          points: live.stroke,
        ),
      );
    }
  }

  Widget _annotationBar(ColorScheme scheme) => Material(
    color: scheme.surfaceContainer,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                for (final (tool, icon, label) in const [
                  (_Tool.highlight, Icons.highlight, 'Surligneur'),
                  (_Tool.pen, Icons.draw_outlined, 'Stylo'),
                  (_Tool.note, Icons.sticky_note_2_outlined, 'Note'),
                  (_Tool.eraser, Icons.auto_fix_normal_outlined, 'Gomme'),
                ])
                  Expanded(
                    child: Semantics(
                      selected: _tool == tool,
                      button: true,
                      label: label,
                      excludeSemantics: true,
                      onTap: () => setState(
                        () => _tool = _tool == tool ? _Tool.none : tool,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(
                          () => _tool = _tool == tool ? _Tool.none : tool,
                        ),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: _tool == tool
                                ? scheme.primaryContainer
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, size: 22),
                              Text(label, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 8),
              for (var i = 0; i < _palette.length; i++)
                Semantics(
                  label: 'Couleur ${_paletteNames[i]}',
                  button: true,
                  selected: _colorIndex == i,
                  excludeSemantics: true,
                  onTap: () => setState(() => _colorIndex = i),
                  child: InkResponse(
                    onTap: () => setState(() => _colorIndex = i),
                    radius: 24,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _palette[i],
                            shape: BoxShape.circle,
                            border: _colorIndex == i
                                ? Border.all(
                                    color: scheme.onSurface,
                                    width: 2.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Annuler la dernière annotation',
                icon: const Icon(Icons.undo),
                onPressed: _annots.isEmpty ? null : _undoAnnotation,
              ),
              TextButton(
                onPressed: () => setState(() {
                  _annotating = false;
                  _tool = _Tool.none;
                }),
                child: const Text('Terminé'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

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
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: const InputDecoration(
                  hintText: 'Rechercher dans le PDF',
                  filled: false,
                  border: InputBorder.none,
                ),
              )
            : Text(
                p.basename(widget.path),
                style: const TextStyle(fontSize: 17),
              ),
        actions: [
          if (_searching)
            IconButton(
              tooltip: 'Fermer la recherche',
              icon: const Icon(Icons.close),
              onPressed: _stopSearch,
            )
          else ...[
            if (doc != null)
              IconButton(
                tooltip: 'Rechercher',
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true),
              ),
            if (doc != null)
              IconButton(
                tooltip: 'Sommaire',
                icon: const Icon(Icons.list_alt_outlined),
                onPressed: _showOutline,
              ),
            if (doc != null)
              IconButton(
                tooltip: _annotating ? 'Quitter les annotations' : 'Annoter',
                icon: Icon(
                  _annotating ? Icons.edit_off_outlined : Icons.edit_outlined,
                ),
                onPressed: () => setState(() {
                  _annotating = !_annotating;
                  if (!_annotating) _tool = _Tool.none;
                }),
              ),
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
                      onStart: () {
                        if (!_drawing) setState(() => _pinching = true);
                      },
                      onUpdate: (s) {
                        if (_drawing) return;
                        setState(
                          () =>
                              _pinch = (s * _zoom).clamp(1.0, _maxZoom) / _zoom,
                        );
                      },
                      onEnd: (s) {
                        if (_drawing) return;
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
                            physics: _pinching || _zoom <= 1 || _drawing
                                ? const NeverScrollableScrollPhysics()
                                : const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: width,
                              child: ListView.builder(
                                controller: _vertical,
                                physics: _pinching || _drawing
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
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _PdfPage(
                                          // A new zoom level builds a new image.
                                          key: ValueKey('$i@$pixelWidth'),
                                          bytes: _render(i, pixelWidth),
                                          night: night,
                                        ),
                                        _PageOverlay(
                                          page: i,
                                          annotations: [
                                            for (final a in _annots)
                                              if (a.page == i) a,
                                          ],
                                          hits: [
                                            for (final (k, h) in _hits.indexed)
                                              if (h.page == i)
                                                for (final r in h.rects)
                                                  (
                                                    Rect.fromLTRB(
                                                      r[0],
                                                      r[1],
                                                      r[2],
                                                      r[3],
                                                    ),
                                                    k == _hit,
                                                  ),
                                          ],
                                          tool: _annotating
                                              ? _tool
                                              : _Tool.none,
                                          live: _live,
                                          liveColor: _palette[_colorIndex],
                                          onTap: _onOverlayTap,
                                          onDrag: _onOverlayDrag,
                                          onDragEnd: _onOverlayDragEnd,
                                          onNote: _editNote,
                                        ),
                                      ],
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
                      bottom: _annotating ? 150 : (_hits.isNotEmpty ? 76 : 20),
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
                    if (_searchBusy)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_searching && (_hits.isNotEmpty || _searchNote != null))
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Material(
                          elevation: 3,
                          borderRadius: BorderRadius.circular(28),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _hits.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(_searchNote!),
                                  )
                                : Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'Résultat précédent',
                                        icon: const Icon(
                                          Icons.keyboard_arrow_up,
                                        ),
                                        onPressed: () => _showHit(
                                          (_hit - 1 + _hits.length) %
                                              _hits.length,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Résultat suivant',
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                        ),
                                        onPressed: () =>
                                            _showHit((_hit + 1) % _hits.length),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_hit + 1} / ${_hits.length} · page ${_hits[_hit].page + 1}',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Liste des résultats',
                                        icon: const Icon(Icons.list),
                                        onPressed: _showResults,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    if (_annotating)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _annotationBar(Theme.of(context).colorScheme),
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

enum _Tool { none, highlight, pen, note, eraser }

/// A drawing in progress on a page (fractions of the page).
class _Live {
  _Live(this.page, {this.start, this.end, this.stroke = const []});
  final int page;
  final Offset? start;
  final Offset? end;
  final List<Offset> stroke;
}

/// Search matches, annotations and drawing gestures laid over one page.
class _PageOverlay extends StatelessWidget {
  const _PageOverlay({
    required this.page,
    required this.annotations,
    required this.hits,
    required this.tool,
    required this.live,
    required this.liveColor,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
    required this.onNote,
  });

  final int page;
  final List<Annotation> annotations;

  /// Search boxes and whether each is the current result.
  final List<(Rect, bool)> hits;
  final _Tool tool;
  final ValueNotifier<_Live?> live;
  final Color liveColor;
  final void Function(int page, Offset at) onTap;
  final void Function(int page, Offset at, {required bool start}) onDrag;
  final VoidCallback onDragEnd;
  final void Function(Annotation note) onNote;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        Offset norm(Offset local) => Offset(
          (local.dx / size.width).clamp(0.0, 1.0),
          (local.dy / size.height).clamp(0.0, 1.0),
        );
        final drawing = tool == _Tool.highlight || tool == _Tool.pen;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ValueListenableBuilder<_Live?>(
                valueListenable: live,
                builder: (_, current, _) => CustomPaint(
                  painter: _MarksPainter(
                    annotations: annotations,
                    hits: hits,
                    live: current != null && current.page == page
                        ? current
                        : null,
                    liveColor: liveColor,
                  ),
                ),
              ),
            ),
            if (tool != _Tool.none)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: drawing
                    ? null
                    : (d) => onTap(page, norm(d.localPosition)),
                onPanStart: drawing
                    ? (d) => onDrag(page, norm(d.localPosition), start: true)
                    : null,
                onPanUpdate: drawing
                    ? (d) => onDrag(page, norm(d.localPosition), start: false)
                    : null,
                onPanEnd: drawing ? (_) => onDragEnd() : null,
                onPanCancel: drawing ? onDragEnd : null,
              ),
            for (final a in annotations)
              if (a.kind == AnnotationKind.note && a.points.isNotEmpty)
                Positioned(
                  left: a.points.first.dx * size.width - 20,
                  top: a.points.first.dy * size.height - 20,
                  width: 40,
                  height: 40,
                  child: Semantics(
                    button: true,
                    label: 'Note : ${a.text}',
                    excludeSemantics: true,
                    onTap: () => onNote(a),
                    child: GestureDetector(
                      onTap: () => onNote(a),
                      child: Center(
                        child: Icon(
                          Icons.sticky_note_2,
                          size: 26,
                          color: Color(a.color),
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({
    required this.annotations,
    required this.hits,
    required this.live,
    required this.liveColor,
  });

  final List<Annotation> annotations;
  final List<(Rect, bool)> hits;
  final _Live? live;
  final Color liveColor;

  Rect _scaled(Rect r, Size s) => Rect.fromLTRB(
    r.left * s.width,
    r.top * s.height,
    r.right * s.width,
    r.bottom * s.height,
  );

  void _stroke(Canvas canvas, Size size, List<Offset> pts, Color color) {
    if (pts.length < 2) return;
    final path = Path()
      ..moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx * size.width, o.dy * size.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.005)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (rect, current) in hits) {
      canvas.drawRect(
        _scaled(rect, size).inflate(1),
        Paint()
          ..color =
              (current ? const Color(0xFFFF9500) : const Color(0xFFFFD60A))
                  .withValues(alpha: current ? 0.55 : 0.4),
      );
    }
    for (final a in annotations) {
      switch (a.kind) {
        case AnnotationKind.highlight:
          for (final r in a.rects) {
            canvas.drawRect(
              _scaled(r, size),
              Paint()
                ..color = Color(a.color).withValues(alpha: 0.38)
                ..blendMode = BlendMode.multiply,
            );
          }
        case AnnotationKind.ink:
          _stroke(canvas, size, a.points, Color(a.color));
        case AnnotationKind.note:
          break; // drawn as a widget so it can be tapped
      }
    }
    final l = live;
    if (l != null) {
      if (l.start != null && l.end != null) {
        canvas.drawRect(
          _scaled(Rect.fromPoints(l.start!, l.end!), size),
          Paint()..color = liveColor.withValues(alpha: 0.38),
        );
      } else {
        _stroke(canvas, size, l.stroke, liveColor);
      }
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true;
}
