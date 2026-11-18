import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import 'note_files.dart';
import 'note_editor_page.dart';
import 'notes_store.dart';

/// Background tints for notes; index 0 is the neutral card colour.
const noteColors = <Color?>[
  null,
  Color(0xFFE5484D),
  Color(0xFFF76B15),
  Color(0xFFFFC53D),
  Color(0xFF30A46C),
  Color(0xFF0A84FF),
  Color(0xFF8E4EC6),
];

Color noteBackground(BuildContext context, int index) {
  final scheme = Theme.of(context).colorScheme;
  final tint = noteColors[index.clamp(0, noteColors.length - 1)];
  if (tint == null) return scheme.surfaceContainer;
  return Color.alphaBlend(
    tint.withValues(alpha: 0.22),
    scheme.surfaceContainer,
  );
}

void openNote(BuildContext context, [Note? note, String? folder]) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NoteEditorPage(note: note, folder: folder ?? ''),
    ),
  );
}

/// Asks for a folder name; null when cancelled.
Future<String?> askNoteFolder(BuildContext context, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Nom du dossier'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Moves [note] to the trash, with a way to take it back.
void deleteNoteWithUndo(BuildContext context, Note note) {
  final store = context.read<NotesStore>();
  final messenger = ScaffoldMessenger.of(context);
  store.moveToTrash(note);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: const Text('Note placée dans la corbeille'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => store.recover(note),
        ),
      ),
    );
}

/// One line of a note as plain text: Markdown markers removed.
String plainLine(String line) => line
    .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '')
    .replaceFirst(RegExp(r'^\s*>\s?'), '')
    .replaceFirst(RegExp(r'^\s*[-*+]\s+(?!\[)'), '• ')
    .replaceAll(RegExp(r'\*\*|~~|`'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!);

final _checkLine = RegExp(r'^\s*[-*+] \[([ xX])\]\s?(.*)$');

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  String _query = '';

  /// A folder name, or null for every note.
  String? _folder;
  bool _showTrash = false;

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    VoidCallback? onLongPress,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 18),
        showCheckmark: false,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    ),
  );

  Future<void> _emptyTrash(NotesStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Vider la corbeille ?'),
        content: const Text('Ces notes seront effacées définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (ok == true) await NoteFiles.remove(await store.emptyTrash());
  }

  void _folderActions(NotesStore store, String name) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name)),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Renommer le dossier'),
              onTap: () async {
                Navigator.pop(sheet);
                final to = await askNoteFolder(context, initial: name);
                if (to != null && to.trim().isNotEmpty) {
                  await store.renameFolder(name, to);
                  if (_folder == name) setState(() => _folder = to.trim());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: const Text('Supprimer le dossier'),
              subtitle: const Text('Les notes sont conservées'),
              onTap: () {
                Navigator.pop(sheet);
                store.deleteFolder(name);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<AppSettings>();
    // A folder that no longer exists falls back to "all".
    final folder = store.folders.contains(_folder) ? _folder : null;
    final base = _query.isEmpty ? store.notes : store.search(_query);
    final notes = _showTrash
        ? store.trash
        : folder == null
        ? base
        : [
            for (final n in base)
              if (n.folder == folder) n,
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_showTrash ? 'Corbeille' : 'Notes'),
        actions: [
          if (_showTrash && store.trash.isNotEmpty)
            TextButton(
              onPressed: () => _emptyTrash(store),
              child: const Text('Vider'),
            ),
          IconButton(
            tooltip: settings.notesGrid
                ? 'Afficher en liste'
                : 'Afficher en grille',
            icon: Icon(
              settings.notesGrid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_rounded,
            ),
            onPressed: () => settings.notesGrid = !settings.notesGrid,
          ),
        ],
      ),
      floatingActionButton: _showTrash
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openNote(context, null, folder),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle note'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Rechercher dans les notes',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(
                  'Toutes',
                  selected: !_showTrash && folder == null,
                  onTap: () => setState(() {
                    _showTrash = false;
                    _folder = null;
                  }),
                ),
                for (final f in store.folders)
                  _chip(
                    f,
                    icon: Icons.folder_outlined,
                    selected: !_showTrash && folder == f,
                    onTap: () => setState(() {
                      _showTrash = false;
                      _folder = f;
                    }),
                    onLongPress: () => _folderActions(store, f),
                  ),
                _chip(
                  store.trash.isEmpty
                      ? 'Corbeille'
                      : 'Corbeille (${store.trash.length})',
                  icon: Icons.delete_outline,
                  selected: _showTrash,
                  onTap: () => setState(() => _showTrash = true),
                ),
              ],
            ),
          ),
          if (_showTrash)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Les notes sont effacées définitivement après 30 jours.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: notes.isEmpty
                ? _EmptyNotes(
                    searching: _query.isNotEmpty,
                    trash: _showTrash,
                    folder: folder,
                  )
                : _NotesList(notes: notes, grid: settings.notesGrid),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.searching, this.trash = false, this.folder});
  final bool searching;
  final bool trash;
  final String? folder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.sticky_note_2_outlined,
              size: 64,
              color: scheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              trash
                  ? 'La corbeille est vide'
                  : searching
                  ? 'Aucune note ne correspond'
                  : folder != null
                  ? 'Aucune note dans ce dossier'
                  : 'Aucune note pour le moment',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!searching && !trash) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => openNote(context, null, folder),
                icon: const Icon(Icons.add),
                label: const Text('Écrire ma première note'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({required this.notes, required this.grid});
  final List<Note> notes;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 0, 16, 96);
    if (!grid) {
      return ListView.separated(
        padding: padding,
        itemCount: notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => NoteCard(note: notes[i], maxLines: 3),
      );
    }
    // Two balanced columns so cards keep their natural height.
    final columns = [<Note>[], <Note>[]];
    for (var i = 0; i < notes.length; i++) {
      columns[i % 2].add(notes[i]);
    }
    return SingleChildScrollView(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < 2; c++) ...[
            if (c == 1) const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  for (final n in columns[c])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NoteCard(note: n, maxLines: 8),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, this.maxLines = 3});
  final Note note;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: noteBackground(context, note.color),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            note.inTrash ? _showTrashActions(context) : openNote(context, note),
        onLongPress: () =>
            note.inTrash ? _showTrashActions(context) : _showActions(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Sans titre' : note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (note.pinned)
                    Icon(Icons.push_pin, size: 16, color: scheme.primary),
                ],
              ),
              if (note.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                _NoteBody(note: note, maxLines: maxLines),
              ],
              if (note.attachments.isNotEmpty || note.folder.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    if (note.folder.isNotEmpty)
                      _Mini(Icons.folder_outlined, note.folder),
                    if (note.attachments.isNotEmpty)
                      _Mini(Icons.attach_file, '${note.attachments.length}'),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                relativeDate(note.updatedAt),
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTrashActions(BuildContext context) {
    final store = context.read<NotesStore>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore_from_trash_outlined),
              title: const Text('Restaurer'),
              onTap: () {
                Navigator.pop(sheet);
                store.recover(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Supprimer définitivement'),
              onTap: () async {
                Navigator.pop(sheet);
                await store.delete(note);
                await NoteFiles.remove(note.attachments);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    final store = context.read<NotesStore>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                note.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(note.pinned ? 'Désépingler' : 'Épingler'),
              onTap: () {
                Navigator.pop(sheet);
                note.pinned = !note.pinned;
                store.save(note, touch: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () {
                Navigator.pop(sheet);
                deleteNoteWithUndo(context, note);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

/// The start of a note; checklist lines can be ticked right from the list.
class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.note, required this.maxLines});
  final Note note;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium;
    final scheme = Theme.of(context).colorScheme;
    final store = context.read<NotesStore>();
    final lines = note.body.split('\n');
    final shown = <Widget>[];
    for (var i = 0; i < lines.length && shown.length < maxLines; i++) {
      final m = _checkLine.firstMatch(lines[i]);
      if (m != null) {
        final done = m[1] != ' ';
        shown.add(
          InkWell(
            onTap: note.inTrash ? null : () => store.toggleCheck(note, i),
            child: Semantics(
              label: '${m[2]}, ${done ? 'cochée' : 'à cocher'}',
              container: true,
              excludeSemantics: true,
              checked: done,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: done ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        m[2]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (lines[i].trim().isNotEmpty) {
        shown.add(
          Text(
            plainLine(lines[i]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: shown,
    );
  }
}
