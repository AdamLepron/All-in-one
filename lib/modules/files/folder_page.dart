import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../music/music_controller.dart';
import '../transfer/transfer_page.dart';
import '../reader/documents.dart';
import 'archives.dart';
import 'file_ops.dart';
import 'files_ui.dart';

/// Browses one folder. [root] is the top of the breadcrumb; [trash] receives
/// deleted items.
class FolderPage extends StatefulWidget {
  const FolderPage({
    super.key,
    required this.path,
    this.root = storageRoot,
    this.trash,
  });
  final String path;
  final String root;
  final Trash? trash;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  List<Entry>? _entries;
  String? _error;
  final _selected = <String>{};
  bool _searching = false;
  String _query = '';
  bool _busy = false;

  late final Trash _trash = widget.trash ?? Trash.device();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = context.read<AppSettings>();
    try {
      final entries = await listFolder(
        widget.path,
        showHidden: settings.filesShowHidden,
        sort: SortBy.values[settings.filesSort],
        ascending: settings.filesAscending,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
        _selected.removeWhere((path) => !entries.any((e) => e.path == path));
      });
    } on FileSystemException catch (e) {
      if (mounted) setState(() => _error = e.osError?.message ?? e.message);
    }
  }

  List<Entry> get _visible {
    final entries = _entries ?? const <Entry>[];
    if (_query.isEmpty) return entries;
    final q = _query.toLowerCase();
    return entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  /// Runs a file operation with a progress bar and reports failures.
  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } on FileSystemException catch (e) {
      if (mounted) {
        showMessage(context, 'Échec : ${e.osError?.message ?? e.message}');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  void _toggle(Entry e) => setState(() {
    if (!_selected.remove(e.path)) _selected.add(e.path);
  });

  Future<void> _open(Entry e) async {
    if (e.isDir) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              FolderPage(path: e.path, root: widget.root, trash: widget.trash),
        ),
      );
      if (mounted) _load();
      return;
    }
    if (e.kind == FileKind.audio &&
        context.read<MusicController>().playPath(e.path)) {
      showMessage(context, 'Lecture de ${e.name}');
      return;
    }
    if (canExtract(e.path)) {
      _archiveActions(e);
      return;
    }
    if (docTypeOf(e.path) != DocType.other) {
      await openDocument(context, e.path);
      return;
    }
    final result = await OpenFilex.open(e.path);
    if (mounted && result.type != ResultType.done) {
      showMessage(
        context,
        result.type == ResultType.noAppToOpen
            ? 'Aucune application ne peut ouvrir ce fichier'
            : "Impossible d'ouvrir ce fichier",
      );
    }
  }

  /// Compresses the selection into a zip next to the files.
  Future<void> _compress() async {
    final paths = _selected.toList();
    setState(_selected.clear);
    await _run(() async {
      final zip = await zipEntities(paths, widget.path);
      if (mounted) showMessage(context, 'Créé : ${p.basename(zip)}');
    });
  }

  Future<void> _extract(Entry e, {required bool inFolder}) async {
    final dest = inFolder
        ? await uniquePath(widget.path, archiveStem(e.path))
        : widget.path;
    setState(() => _busy = true);
    try {
      final r = await extractArchive(e.path, dest);
      if (mounted) {
        showMessage(
          context,
          '${r.files} fichier${r.files > 1 ? 's' : ''} extrait${r.files > 1 ? 's' : ''}'
          '${r.skipped > 0 ? ' · ${r.skipped} entrée(s) ignorée(s) par sécurité' : ''}',
        );
      }
    } on Object {
      if (mounted) showMessage(context, "Impossible d'extraire cette archive");
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  void _archiveActions(Entry e) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: KindIcon(e.kind), title: Text(e.name)),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('Extraire dans un nouveau dossier'),
              onTap: () {
                Navigator.pop(sheet);
                _extract(e, inFolder: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('Extraire ici'),
              onTap: () {
                Navigator.pop(sheet);
                _extract(e, inFolder: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Ouvrir avec une autre application'),
              onTap: () {
                Navigator.pop(sheet);
                OpenFilex.open(e.path);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newFolder() async {
    final name = await askName(
      context,
      title: 'Nouveau dossier',
      action: 'Créer',
    );
    if (name == null) return;
    await _run(() async {
      final path = p.join(widget.path, name);
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        throw const FileSystemException('Un élément porte déjà ce nom');
      }
      await Directory(path).create();
    });
  }

  Future<void> _rename() async {
    final path = _selected.single;
    final name = await askName(
      context,
      title: 'Renommer',
      initial: p.basename(path),
      action: 'Renommer',
    );
    if (name == null) return;
    setState(_selected.clear);
    await _run(() => renameEntity(path, name));
  }

  Future<void> _delete() async {
    final paths = _selected.toList();
    setState(_selected.clear);
    final items = <TrashItem>[];
    await _run(() async {
      for (final path in paths) {
        items.add(await _trash.put(path));
      }
    });
    if (!mounted || items.isEmpty) return;
    showMessage(
      context,
      items.length == 1
          ? '« ${items.first.name} » déplacé dans la corbeille'
          : '${items.length} éléments déplacés dans la corbeille',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => _run(() async {
          for (final item in items) {
            await _trash.restore(item);
          }
        }),
      ),
    );
  }

  void _toClipboard({required bool move}) {
    context.read<FilesClipboard>().set(_selected.toList(), move: move);
    setState(_selected.clear);
  }

  Future<void> _paste() async {
    final clipboard = context.read<FilesClipboard>();
    final paths = clipboard.paths;
    final move = clipboard.move;
    clipboard.clear();
    await _run(() async {
      for (final path in paths) {
        move
            ? await moveEntity(path, widget.path)
            : await copyEntity(path, widget.path);
      }
    });
    if (mounted) {
      final n = paths.length;
      showMessage(
        context,
        '$n élément${n > 1 ? 's' : ''} ${move ? 'déplacé' : 'copié'}${n > 1 ? 's' : ''}',
      );
    }
  }

  Future<void> _share() async {
    final files = [
      for (final path in _selected)
        if (FileSystemEntity.isFileSync(path)) XFile(path),
    ];
    if (files.isEmpty) {
      showMessage(context, 'Seuls les fichiers peuvent être partagés');
      return;
    }
    setState(_selected.clear);
    await SharePlus.instance.share(ShareParams(files: files));
  }

  Future<void> _properties() async {
    final entry = _entries!.firstWhere((e) => e.path == _selected.single);
    final size = sizeOf(entry.path);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: KindIcon(entry.kind), title: Text(entry.name)),
            ListTile(
              dense: true,
              title: const Text('Emplacement'),
              subtitle: Text(p.dirname(entry.path)),
              trailing: IconButton(
                tooltip: 'Copier le chemin',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: entry.path)),
              ),
            ),
            ListTile(
              dense: true,
              title: const Text('Taille'),
              subtitle: FutureBuilder<int>(
                future: size,
                builder: (_, snap) => Text(
                  snap.hasData
                      ? '${formatBytes(snap.data!)}${entry.isDir ? ' · ${entry.size} élément${entry.size > 1 ? 's' : ''}' : ''}'
                      : 'Calcul…',
                ),
              ),
            ),
            ListTile(
              dense: true,
              title: const Text('Modifié'),
              subtitle: Text(relativeDate(entry.modified)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSort() {
    final settings = context.read<AppSettings>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, label) in const ['Nom', 'Date', 'Taille'].indexed)
              ListTile(
                title: Text(label),
                selected: settings.filesSort == i,
                trailing: settings.filesSort == i
                    ? Icon(
                        settings.filesAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                      )
                    : null,
                onTap: () {
                  // Tapping the active criterion flips the direction.
                  if (settings.filesSort == i) {
                    settings.filesAscending = !settings.filesAscending;
                  } else {
                    settings.filesSort = i;
                  }
                  Navigator.pop(sheet);
                  _load();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final clipboard = context.watch<FilesClipboard>();
    final selecting = _selected.isNotEmpty;
    final visible = _visible;
    final title = widget.path == widget.root
        ? (widget.root == storageRoot ? 'Stockage interne' : 'Carte SD')
        : p.basename(widget.path);

    return PopScope(
      canPop: !selecting && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _selected.clear();
          _searching = false;
          _query = '';
        });
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text('${_selected.length}'),
                actions: [
                  IconButton(
                    tooltip: 'Copier',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => _toClipboard(move: false),
                  ),
                  IconButton(
                    tooltip: 'Déplacer',
                    icon: const Icon(Icons.drive_file_move_outline),
                    onPressed: () => _toClipboard(move: true),
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _delete,
                  ),
                  PopupMenuButton<VoidCallback>(
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _share,
                        child: const Text('Partager'),
                      ),
                      PopupMenuItem(
                        value: () {
                          final paths = _selected.toList();
                          setState(_selected.clear);
                          sendByWifi(context, paths);
                        },
                        child: const Text('Envoyer par Wi-Fi'),
                      ),
                      PopupMenuItem(
                        value: _compress,
                        child: const Text('Compresser en .zip'),
                      ),
                      if (_selected.length == 1) ...[
                        PopupMenuItem(
                          value: _rename,
                          child: const Text('Renommer'),
                        ),
                        PopupMenuItem(
                          value: _properties,
                          child: const Text('Propriétés'),
                        ),
                      ],
                      PopupMenuItem(
                        value: () => setState(
                          () => _selected.addAll(visible.map((e) => e.path)),
                        ),
                        child: const Text('Tout sélectionner'),
                      ),
                    ],
                  ),
                ],
              )
            : AppBar(
                title: _searching
                    ? TextField(
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          hintText: 'Rechercher dans ce dossier',
                          filled: false,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(title),
                actions: [
                  IconButton(
                    tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
                    icon: Icon(_searching ? Icons.close : Icons.search),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      _query = '';
                    }),
                  ),
                  IconButton(
                    tooltip: 'Trier',
                    icon: const Icon(Icons.sort_rounded),
                    onPressed: _showSort,
                  ),
                  PopupMenuButton<VoidCallback>(
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _newFolder,
                        child: const Text('Nouveau dossier'),
                      ),
                      PopupMenuItem(
                        value: () {
                          settings.filesShowHidden = !settings.filesShowHidden;
                          _load();
                        },
                        child: Text(
                          settings.filesShowHidden
                              ? 'Masquer les fichiers cachés'
                              : 'Afficher les fichiers cachés',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            _Breadcrumb(path: widget.path, root: widget.root),
            Expanded(child: _body(visible)),
          ],
        ),
        bottomNavigationBar: clipboard.isEmpty
            ? null
            : _PasteBar(clipboard: clipboard, onPaste: _paste),
      ),
    );
  }

  Widget _body(List<Entry> visible) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return _Empty(
        icon: Icons.lock_outline,
        text: 'Dossier inaccessible\n$_error',
      );
    }
    if (_entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isEmpty) {
      return _Empty(
        icon: _query.isEmpty ? Icons.folder_open : Icons.search_off,
        text: _query.isEmpty ? 'Ce dossier est vide' : 'Aucun résultat',
        action: _query.isEmpty
            ? FilledButton.tonalIcon(
                onPressed: _newFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Nouveau dossier'),
              )
            : null,
      );
    }
    final selecting = _selected.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: visible.length,
        itemBuilder: (_, i) {
          final e = visible[i];
          final selected = _selected.contains(e.path);
          return ListTile(
            selected: selected,
            selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
            leading: selected
                ? CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary,
                    child: Icon(Icons.check, color: scheme.onPrimary),
                  )
                : KindIcon(e.kind),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${e.isDir ? '${e.size} élément${e.size > 1 ? 's' : ''}' : formatBytes(e.size)} · ${relativeDate(e.modified)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: e.isDir && !selecting
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: () => selecting ? _toggle(e) : _open(e),
            onLongPress: () {
              HapticFeedback.selectionClick();
              _toggle(e);
            },
          );
        },
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.root});
  final String path;
  final String root;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = p
        .split(p.relative(path, from: root))
        .where((s) => s != '.')
        .toList();
    final labels = ['Stockage', ...parts];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true, // keeps the current folder in view
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (_, _) =>
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
        itemBuilder: (context, reversed) {
          final i = labels.length - 1 - reversed;
          final last = i == labels.length - 1;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: last
                ? null
                : () {
                    // Each level is one pushed page.
                    var pops = labels.length - 1 - i;
                    Navigator.of(context).popUntil((_) => pops-- == 0);
                  },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontWeight: last ? FontWeight.w700 : FontWeight.w500,
                    color: last ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PasteBar extends StatelessWidget {
  const _PasteBar({required this.clipboard, required this.onPaste});
  final FilesClipboard clipboard;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = clipboard.paths.length;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$n élément${n > 1 ? 's' : ''} à ${clipboard.move ? 'déplacer' : 'copier'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: clipboard.clear,
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Coller ici'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
