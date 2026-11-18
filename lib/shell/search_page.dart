import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/modules.dart';
import '../core/util.dart';
import '../modules/calendar/calendar_page.dart' show eventColors;
import '../modules/calendar/event_editor_page.dart';
import '../modules/docs/docs_store.dart';
import '../modules/docs/document_editor_page.dart';
import '../modules/files/file_ops.dart';
import '../modules/files/files_ui.dart';
import '../modules/files/folder_page.dart';
import '../modules/gallery/media_grid.dart';
import '../modules/gallery/media_library.dart';
import '../modules/gallery/viewer_page.dart';
import '../modules/music/music_controller.dart';
import '../modules/reader/documents.dart';
import '../modules/recorder/recorder_controller.dart';
import '../modules/video/video_player_page.dart';
import '../modules/music/music_page.dart';
import '../modules/notes/notes_page.dart';
import '../modules/notes/notes_store.dart';
import '../modules/scanner/scan_store.dart';
import '../modules/scanner/scanner_page.dart';
import '../modules/tasks/organizer_store.dart';
import '../modules/tasks/tasks_page.dart';
import 'search_sources.dart';
import 'widgets.dart';

/// Universal search across modules and note contents.
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    this.documentsDirectory = docsDirectory,
    this.filesRoot = storageRoot,
    this.canSearchFiles = _hasFileAccess,
  });

  /// Where the documents written in the app are.
  final String documentsDirectory;

  /// Where files are searched by name.
  final String filesRoot;

  /// Whether files may be searched. Never asks: the search does not show a
  /// permission dialog by itself.
  final Future<bool> Function() canSearchFiles;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

Future<bool> _hasFileAccess() async {
  try {
    return await Permission.manageExternalStorage.isGranted;
  } on Object {
    return false;
  }
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  // Documents and files are searched on disk, so after a short pause.
  Timer? _pause;
  int _generation = 0;
  List<DocHit> _docs = const [];
  List<FileHit> _files = const [];
  bool _searching = false;

  @override
  void dispose() {
    _pause?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _pause?.cancel();
    final q = value.trim();
    _generation++;
    if (q.length < 2) {
      setState(() {
        _docs = const [];
        _files = const [];
        _searching = false;
      });
      return;
    }
    _pause = Timer(const Duration(milliseconds: 300), () => _searchDisk(q));
  }

  Future<void> _searchDisk(String q) async {
    final generation = ++_generation;
    setState(() => _searching = true);
    final docs = await searchDocuments(widget.documentsDirectory, q);
    final files = await widget.canSearchFiles()
        ? await searchFileNames(widget.filesRoot, q)
        : <FileHit>[];
    // A newer search started meanwhile: this answer is stale.
    if (!mounted || generation != _generation) return;
    setState(() {
      _docs = docs;
      _files = files;
      _searching = false;
    });
  }

  Future<void> _openFile(FileHit hit) async {
    if (hit.isDir) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FolderPage(path: hit.path)),
      );
    } else if (docTypeOf(hit.path) != DocType.other) {
      await openDocument(context, hit.path);
    } else {
      final result = await OpenFilex.open(hit.path);
      if (mounted && result.type != ResultType.done) {
        showMessage(context, "Aucune application ne peut ouvrir ce fichier");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<NotesStore>();
    final q = _query.trim().toLowerCase();
    final moduleHits = q.isEmpty
        ? <AppModule>[]
        : modules
              .where(
                (m) =>
                    m.name.toLowerCase().contains(q) ||
                    m.description.toLowerCase().contains(q),
              )
              .toList();
    final noteHits = store.search(q);
    final scanHits = q.isEmpty
        ? const <Scan>[]
        : context.watch<ScanStore>().search(q).take(6).toList();
    final taskHits = q.isEmpty
        ? const <Task>[]
        : context
              .watch<OrganizerStore>()
              .open
              .where((t) => t.title.toLowerCase().contains(q))
              .take(8)
              .toList();
    final eventHits = searchEvents(context.watch<OrganizerStore>().events, q);
    final mediaHits = searchMedia(context.watch<MediaLibrary>().items, q);
    final recordingHits = searchRecordings(
      context.watch<RecorderController>().recordings,
      q,
    );
    final music = context.watch<MusicController>();
    final songHits = q.isEmpty
        ? const <Never>[]
        : music.songs.where((s) => s.matches(q)).take(8).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Recherche')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Modules, notes, fichiers, événements…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: q.isEmpty
                ? _Hint(
                    icon: Icons.search,
                    text: 'Cherchez un module, une note, un fichier, un événement ou un morceau',
                    color: scheme.outline,
                  )
                : moduleHits.isEmpty &&
                      noteHits.isEmpty &&
                      songHits.isEmpty &&
                      taskHits.isEmpty &&
                      scanHits.isEmpty &&
                      eventHits.isEmpty &&
                      mediaHits.isEmpty &&
                      recordingHits.isEmpty &&
                      _docs.isEmpty &&
                      _files.isEmpty
                ? _searching
                      ? const Center(child: CircularProgressIndicator())
                      : _Hint(
                          icon: Icons.search_off,
                          text: 'Aucun résultat pour « ${_query.trim()} »',
                          color: scheme.outline,
                        )
                : ListView(
                    children: [
                      if (moduleHits.isNotEmpty) const _GroupLabel('Modules'),
                      for (final m in moduleHits)
                        ListTile(
                          leading: ModuleIcon(m, size: 40),
                          title: Text(m.name),
                          subtitle: Text(m.description),
                          trailing: m.available ? null : const SoonBadge(),
                          onTap: () => m.open(context),
                        ),
                      if (songHits.isNotEmpty) const _GroupLabel('Musique'),
                      for (final (i, s) in songHits.indexed)
                        SongTile(s, onTap: () => music.play(songHits, i)),
                      if (taskHits.isNotEmpty) const _GroupLabel('Tâches'),
                      for (final t in taskHits) TaskTile(t),
                      if (scanHits.isNotEmpty) const _GroupLabel('Scans'),
                      for (final scan in scanHits)
                        ListTile(
                          leading: ModuleIcon(moduleById('scanner'), size: 40),
                          title: Text(
                            scan.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${scan.pages} page${scan.pages > 1 ? 's' : ''} · ${relativeDate(scan.date)}',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ScanDetailPage(scan: scan),
                            ),
                          ),
                        ),
                      if (eventHits.isNotEmpty) const _GroupLabel('Événements'),
                      for (final e in eventHits)
                        ListTile(
                          leading: Container(
                            width: 5,
                            height: 38,
                            decoration: BoxDecoration(
                              color:
                                  eventColors[e.color.clamp(
                                    0,
                                    eventColors.length - 1,
                                  )],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          title: Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${dayLabel(e.start)}${e.location.isEmpty ? '' : ' · ${e.location}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EventEditorPage(
                                event: e,
                                day: dayOf(e.start),
                              ),
                            ),
                          ),
                        ),
                      if (mediaHits.isNotEmpty)
                        const _GroupLabel('Photos et vidéos'),
                      for (final (i, m) in mediaHits.indexed)
                        ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: MediaThumb(m, showDuration: false),
                            ),
                          ),
                          title: Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${m.album} · ${relativeDate(m.date)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => m.video
                                  ? VideoPlayerPage(media: m)
                                  : ViewerPage(
                                      items: mediaHits,
                                      initialIndex: i,
                                    ),
                            ),
                          ),
                        ),
                      if (recordingHits.isNotEmpty)
                        const _GroupLabel('Enregistrements'),
                      for (final r in recordingHits)
                        ListTile(
                          leading: ModuleIcon(moduleById('recorder'), size: 40),
                          title: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(relativeDate(r.date)),
                          onTap: () => moduleById('recorder').open(context),
                        ),
                      if (_docs.isNotEmpty) const _GroupLabel('Documents'),
                      for (final d in _docs)
                        ListTile(
                          leading: ModuleIcon(
                            moduleById('doc_editor'),
                            size: 40,
                          ),
                          title: Text(
                            d.doc.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            d.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DocumentEditorPage(
                                path: d.doc.path,
                                directory: widget.documentsDirectory,
                              ),
                            ),
                          ),
                        ),
                      if (_files.isNotEmpty) const _GroupLabel('Fichiers'),
                      for (final f in _files)
                        ListTile(
                          leading: KindIcon(
                            f.isDir ? FileKind.folder : kindOfPath(f.path),
                          ),
                          title: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            p
                                .dirname(f.path)
                                .replaceFirst(widget.filesRoot, 'Stockage'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openFile(f),
                        ),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      if (noteHits.isNotEmpty) const _GroupLabel('Notes'),
                      for (final n in noteHits)
                        ListTile(
                          leading: ModuleIcon(moduleById('notes'), size: 40),
                          title: Text(
                            n.title.isEmpty ? 'Sans titre' : n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            n.body.isEmpty ? relativeDate(n.updatedAt) : n.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => openNote(context, n),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
