import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/util.dart';
import '../../shell/search_sources.dart';
import '../music/music_controller.dart';
import '../reader/documents.dart';
import 'categories.dart';
import 'file_ops.dart';
import 'files_ui.dart';
import 'folder_page.dart';

/// Opens a file with the right part of the app, or another app.
Future<void> openFileAt(BuildContext context, String path) async {
  if (kindOfPath(path) == FileKind.audio &&
      context.read<MusicController>().playPath(path)) {
    showMessage(context, 'Lecture de ${p.basename(path)}');
    return;
  }
  if (docTypeOf(path) != DocType.other) {
    await openDocument(context, path);
    return;
  }
  final result = await OpenFilex.open(path);
  if (context.mounted && result.type != ResultType.done) {
    showMessage(
      context,
      result.type == ResultType.noAppToOpen
          ? 'Aucune application ne peut ouvrir ce fichier'
          : "Impossible d'ouvrir ce fichier",
    );
  }
}

/// Where a file lives, for display: the path without the storage root.
String shortFolder(String path) {
  var dir = p.dirname(path);
  if (dir.startsWith(storageRoot)) {
    dir = dir.replaceFirst(storageRoot, 'Stockage');
  }
  return dir;
}

/// Every file of one category, most recent first.
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.category, required this.roots});
  final FileCategory category;
  final List<String> roots;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  CategoryScan? _scan;

  @override
  void initState() {
    super.initState();
    scanCategory(widget.roots, widget.category).then((s) {
      if (mounted) setState(() => _scan = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.label)),
      body: scan == null
          ? const Center(child: CircularProgressIndicator())
          : scan.entries.isEmpty
          ? Center(
              child: Text(
                'Aucun fichier',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              children: [
                if (!scan.complete)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Liste partielle : les fichiers les plus récents sont affichés.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final e in scan.entries)
                  ListTile(
                    leading: KindIcon(e.kind),
                    title: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatBytes(e.size)} · ${relativeDate(e.modified)} · ${shortFolder(e.path)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => openFileAt(context, e.path),
                    onLongPress: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FolderPage(path: p.dirname(e.path)),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Search by file name across every storage.
class FileSearchPage extends StatefulWidget {
  const FileSearchPage({super.key, required this.roots});
  final List<String> roots;

  @override
  State<FileSearchPage> createState() => _FileSearchPageState();
}

class _FileSearchPageState extends State<FileSearchPage> {
  Timer? _pause;
  int _generation = 0;
  String _query = '';
  List<FileHit> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _pause?.cancel();
    super.dispose();
  }

  void _changed(String value) {
    _pause?.cancel();
    final q = value.trim();
    final generation = ++_generation;
    setState(() => _query = q);
    if (q.length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    _pause = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      final all = <FileHit>[];
      for (final root in widget.roots) {
        all.addAll(
          await searchFileNames(
            root,
            q,
            limit: 60,
            maxVisited: 200000,
            maxTime: const Duration(seconds: 6),
          ),
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _hits = all;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: _changed,
          decoration: const InputDecoration(
            hintText: 'Rechercher dans tous les fichiers',
            filled: false,
            border: InputBorder.none,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _hits.isEmpty
                ? Center(
                    child: Text(
                      _query.length < 2
                          ? 'Tapez au moins 2 lettres'
                          : _searching
                          ? ''
                          : 'Aucun résultat',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    children: [
                      for (final h in _hits)
                        ListTile(
                          leading: KindIcon(
                            h.isDir ? FileKind.folder : kindOfPath(h.path),
                          ),
                          title: Text(
                            p.basename(h.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            shortFolder(h.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => h.isDir
                              ? Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FolderPage(path: h.path),
                                  ),
                                )
                              : openFileAt(context, h.path),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
