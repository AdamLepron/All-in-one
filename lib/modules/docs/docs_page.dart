import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'docs_store.dart';
import 'document_editor_page.dart';

/// Library of documents written in the app.
class DocsPage extends StatefulWidget {
  const DocsPage({super.key, this.directory = docsDirectory});
  final String directory;

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  List<DocEntry>? _docs;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (widget.directory == docsDirectory &&
        !await ensureFullFileAccess(context)) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final docs = await listDocuments(widget.directory);
    if (mounted) {
      setState(() {
        _docs = docs;
        _denied = false;
      });
    }
  }

  Future<void> _open([String? path]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DocumentEditorPage(path: path, directory: widget.directory),
      ),
    );
    if (mounted) _load();
  }

  void _actions(DocEntry doc) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renommer'),
              onTap: () async {
                Navigator.pop(sheet);
                final name = await askName(
                  context,
                  title: 'Renommer',
                  initial: doc.title,
                  action: 'Renommer',
                );
                if (name == null) return;
                try {
                  await renameEntity(doc.path, '$name${p.extension(doc.path)}');
                } on FileSystemException catch (e) {
                  if (mounted) showMessage(context, e.message);
                }
                if (mounted) _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager'),
              onTap: () {
                Navigator.pop(sheet);
                SharePlus.instance.share(ShareParams(files: [XFile(doc.path)]));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () async {
                Navigator.pop(sheet);
                final trash = Trash.device();
                final item = await trash.put(doc.path);
                await _load();
                if (!mounted) return;
                showMessage(
                  context,
                  '« ${doc.title} » déplacé dans la corbeille',
                  action: SnackBarAction(
                    label: 'Annuler',
                    onPressed: () async {
                      await trash.restore(item);
                      if (mounted) _load();
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final docs = _docs;
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau document'),
      ),
      body: _denied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "L'accès aux fichiers est nécessaire pour enregistrer vos documents dans Documents / All-in-One.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _load,
                      child: const Text("Autoriser l'accès"),
                    ),
                  ],
                ),
              ),
            )
          : docs == null
          ? const Center(child: CircularProgressIndicator())
          : docs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_document, size: 72, color: scheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Aucun document',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Titres, listes, cases à cocher, liens, mise en forme : écrivez, puis exportez en PDF.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final d in docs)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondaryContainer,
                      child: Icon(
                        Icons.description_outlined,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    title: Text(
                      d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      d.preview.isEmpty
                          ? relativeDate(d.modified)
                          : '${d.preview}\n${relativeDate(d.modified)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: d.preview.isNotEmpty,
                    onTap: () => _open(d.path),
                    onLongPress: () => _actions(d),
                    trailing: IconButton(
                      tooltip: 'Options',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _actions(d),
                    ),
                  ),
              ],
            ),
    );
  }
}
