import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../core/util.dart';
import '../docs/pdf_export.dart' show PdfFonts;
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../reader/pdf_view_page.dart';
import 'scan_pdf.dart';
import 'scan_store.dart';

/// Reads the text of each picture, with its position. Null when text
/// recognition is not available on this phone.
Future<List<PageOcr>?> readPagesOcr(List<String> paths) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final pages = <PageOcr>[];
    for (final path in paths) {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      final codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final width = frame.image.width, height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      pages.add(
        PageOcr(width, height, [
          for (final block in result.blocks)
            for (final line in block.lines)
              OcrLine(
                line.text,
                line.boundingBox.left,
                line.boundingBox.top,
                line.boundingBox.right,
                line.boundingBox.bottom,
              ),
        ]),
      );
    }
    return pages;
  } on PlatformException {
    return null;
  } finally {
    await recognizer.close();
  }
}

/// Library of scanned documents; the button starts a new scan.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<ScanStore>();
    WidgetsBinding.instance.addPostFrameCallback((_) => store.load());
  }

  /// Opens the system document scanner, then reads the text of each page.
  Future<void> _scan() async {
    final store = context.read<ScanStore>();
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg, DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 30,
        isGalleryImport: true,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      if (images.isEmpty) return;
      if (mounted) setState(() => _busy = true);

      final ocr = await readPagesOcr([for (final i in images) localPath(i)]);
      final scan = await store.add(
        images: images,
        pdf: result.pdf?.uri,
        text: ocr == null
            ? ''
            : ocr
                  .map((o) => o.text.trim())
                  .where((t) => t.isNotEmpty)
                  .join('\n'),
        ocr: ocr,
        fonts: await PdfFonts.load(),
      );
      if (mounted) _open(scan);
    } on PlatformException catch (e) {
      // The scanner reports a cancelled scan as an error; stay silent then.
      final cancelled = (e.message ?? '').toLowerCase().contains('cancel');
      if (mounted && !cancelled) {
        showMessage(
          context,
          'Le scanner a besoin des services Google Play, à jour, sur ce téléphone',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        showMessage(context, 'Scanner indisponible sur cet appareil');
      }
    } finally {
      await scanner.close().catchError((Object _) {});
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(Scan scan) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => ScanDetailPage(scan: scan)));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ScanStore>();
    final scheme = Theme.of(context).colorScheme;
    final scans = store.search(_query);

    return Scaffold(
      appBar: AppBar(title: const Text('Scanner')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scanner'),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (store.scans.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Rechercher dans le texte des scans',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          Expanded(
            child: !store.loaded
                ? const SizedBox.shrink()
                : store.scans.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.document_scanner_outlined,
                            size: 72,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun document scanné',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Les bords sont détectés automatiquement et le texte devient cherchable.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : scans.isEmpty
                ? const Center(child: Text('Aucun résultat'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: scans.length,
                    itemBuilder: (_, i) {
                      final s = scans[i];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 58,
                            child: Image.file(
                              File(s.page(0)),
                              fit: BoxFit.cover,
                              cacheWidth: 132,
                              errorBuilder: (_, _, _) => ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: const Icon(Icons.description_outlined),
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${s.pages} page${s.pages > 1 ? 's' : ''} · ${relativeDate(s.date)}',
                        ),
                        onTap: () => _open(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pages of one scan with its actions.
class ScanDetailPage extends StatefulWidget {
  const ScanDetailPage({super.key, required this.scan});
  final Scan scan;

  @override
  State<ScanDetailPage> createState() => _ScanDetailPageState();
}

class _ScanDetailPageState extends State<ScanDetailPage> {
  int _page = 0;

  Scan get scan => widget.scan;
  bool get _hasPdf => File(scan.pdf).existsSync();

  bool _needsOcr = false;

  @override
  void initState() {
    super.initState();
    context.read<ScanStore>().ocrOf(scan).then((o) {
      if (mounted) setState(() => _needsOcr = o == null);
    });
  }

  Future<void> _managePages() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ScanPagesPage(scan: scan)),
    );
    if (changed == true && mounted) {
      if (_page >= scan.pages) _page = scan.pages - 1;
      PaintingBinding.instance.imageCache.clear();
      setState(() {});
    }
  }

  /// Reads the pages of an older scan so its PDF can be searched.
  Future<void> _makeSearchable() async {
    final store = context.read<ScanStore>();
    showMessage(context, 'Lecture du texte des pages…');
    final ocr = await readPagesOcr([
      for (var i = 0; i < scan.pages; i++) scan.page(i),
    ]);
    if (ocr == null) {
      if (mounted) showMessage(context, 'Reconnaissance du texte indisponible');
      return;
    }
    await store.storeOcr(scan, ocr, await PdfFonts.load());
    if (mounted) {
      setState(() => _needsOcr = false);
      showMessage(context, 'Le PDF est maintenant cherchable');
    }
  }

  Future<void> _rename() async {
    final store = context.read<ScanStore>();
    final name = await askName(
      context,
      title: 'Renommer',
      initial: scan.title,
      action: 'Renommer',
    );
    if (name != null) {
      await store.rename(scan, name);
      if (mounted) setState(() {});
    }
  }

  /// Copies the PDF to Documents/Scans so other apps can find it.
  Future<void> _export() async {
    if (!await ensureFullFileAccess(context)) return;
    try {
      final dir = p.join(storageRoot, 'Documents', 'Scans');
      await Directory(dir).create(recursive: true);
      final target = await uniquePath(
        dir,
        '${scan.title.replaceAll('…', '')}.pdf',
      );
      await File(scan.pdf).copy(target);
      await MediaChannel.scan([target]);
      if (mounted) showMessage(context, 'Enregistré dans Documents/Scans');
    } on FileSystemException {
      if (mounted) showMessage(context, "L'enregistrement a échoué");
    }
  }

  void _showText() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Texte reconnu',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: scan.text));
                    Navigator.pop(sheet);
                    showMessage(context, 'Texte copié');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copier'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(scan.text),
          ],
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final store = context.read<ScanStore>();
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Supprimer ce scan ?'),
        content: Text('« ${scan.title} » sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.delete(scan);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerHighest,
      appBar: AppBar(
        title: Text(scan.title, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Partager le PDF',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                files: [
                  if (_hasPdf)
                    XFile(scan.pdf)
                  else
                    for (var i = 0; i < scan.pages; i++) XFile(scan.page(i)),
                ],
              ),
            ),
          ),
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(value: _rename, child: const Text('Renommer')),
              PopupMenuItem(
                value: _managePages,
                child: const Text('Réorganiser les pages'),
              ),
              if (_needsOcr)
                PopupMenuItem(
                  value: _makeSearchable,
                  child: const Text('Rendre le PDF cherchable'),
                ),
              if (_hasPdf) ...[
                PopupMenuItem(
                  value: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfViewPage(path: scan.pdf),
                    ),
                  ),
                  child: const Text('Ouvrir le PDF'),
                ),
                PopupMenuItem(
                  value: _export,
                  child: const Text('Enregistrer dans Documents'),
                ),
              ],
              PopupMenuItem(
                value: () => SharePlus.instance.share(
                  ShareParams(
                    files: [
                      for (var i = 0; i < scan.pages; i++) XFile(scan.page(i)),
                    ],
                  ),
                ),
                child: const Text('Partager en images'),
              ),
              PopupMenuItem(value: _delete, child: const Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              itemCount: scan.pages,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.file(
                    File(scan.page(i)),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Text('Page ${_page + 1} / ${scan.pages}'),
                    const Spacer(),
                    if (scan.text.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: _showText,
                        icon: const Icon(Icons.text_snippet_outlined, size: 18),
                        label: const Text('Texte reconnu'),
                      )
                    else
                      Text(
                        'Aucun texte reconnu',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reorder, turn and delete the pages of a scan.
class ScanPagesPage extends StatefulWidget {
  const ScanPagesPage({super.key, required this.scan});
  final Scan scan;

  @override
  State<ScanPagesPage> createState() => _ScanPagesPageState();
}

class _PageEntry {
  _PageEntry(this.index);
  final int index;
  int turns = 0;
}

class _ScanPagesPageState extends State<ScanPagesPage> {
  late final List<_PageEntry> _entries = [
    for (var i = 0; i < widget.scan.pages; i++) _PageEntry(i),
  ];
  bool _busy = false;

  bool get _changed =>
      _entries.length != widget.scan.pages ||
      [for (final e in _entries) e.index]
          .asMap()
          .entries
          .any((m) => m.key != m.value) ||
      _entries.any((e) => e.turns % 4 != 0);

  Future<void> _apply() async {
    final store = context.read<ScanStore>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final fonts = await PdfFonts.load();
      // Pictures are turned first, under their current numbers.
      for (final e in _entries) {
        if (e.turns % 4 != 0) {
          await store.rotatePage(widget.scan, e.index, e.turns, fonts: fonts);
        }
      }
      await store.arrangePages(widget.scan, [
        for (final e in _entries) e.index,
      ], fonts: fonts);
      navigator.pop(true);
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, 'Impossible de modifier les pages');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pages'),
        actions: [
          TextButton(
            onPressed: _changed && !_busy ? _apply : null,
            child: const Text('Appliquer'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Faites glisser une page par sa poignée pour la déplacer.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _entries.length,
              onReorderItem: (from, to) =>
                  setState(() => _entries.insert(to, _entries.removeAt(from))),
              itemBuilder: (_, position) {
                final e = _entries[position];
                return ListTile(
                  key: ValueKey(e.index),
                  leading: SizedBox(
                    width: 56,
                    height: 72,
                    child: RotatedBox(
                      quarterTurns: e.turns,
                      child: Image.file(
                        File(widget.scan.page(e.index)),
                        cacheWidth: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  title: Text('Page ${position + 1}'),
                  subtitle: e.index != position
                      ? Text('Était la page ${e.index + 1}')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Tourner la page ${position + 1}',
                        icon: const Icon(Icons.rotate_right),
                        onPressed: _busy
                            ? null
                            : () => setState(() => e.turns = (e.turns + 1) % 4),
                      ),
                      IconButton(
                        tooltip: 'Supprimer la page ${position + 1}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy || _entries.length == 1
                            ? null
                            : () => setState(() => _entries.removeAt(position)),
                      ),
                      ReorderableDragStartListener(
                        index: position,
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
