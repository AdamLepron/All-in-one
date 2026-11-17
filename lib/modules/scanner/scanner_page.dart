import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../reader/pdf_view_page.dart';
import 'scan_store.dart';

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

      final text = StringBuffer();
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        for (final image in images) {
          final page = await recognizer.processImage(
            InputImage.fromFilePath(localPath(image)),
          );
          if (page.text.trim().isNotEmpty) text.writeln(page.text.trim());
        }
      } on PlatformException {
        // Text recognition unavailable: keep the scan without its text.
      } finally {
        await recognizer.close();
      }

      final scan = await store.add(
        images: images,
        pdf: result.pdf?.uri,
        text: text.toString().trim(),
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
