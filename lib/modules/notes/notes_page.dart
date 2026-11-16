import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
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
  return Color.alphaBlend(tint.withValues(alpha: 0.22), scheme.surfaceContainer);
}

void openNote(BuildContext context, [Note? note]) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
  );
}

void deleteNoteWithUndo(BuildContext context, Note note) {
  final store = context.read<NotesStore>();
  final messenger = ScaffoldMessenger.of(context);
  store.delete(note);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: const Text('Note supprimée'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Annuler', onPressed: () => store.restore(note)),
    ));
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<AppSettings>();
    final notes = _query.isEmpty ? store.notes : store.search(_query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            tooltip: settings.notesGrid ? 'Afficher en liste' : 'Afficher en grille',
            icon: Icon(settings.notesGrid
                ? Icons.view_agenda_outlined
                : Icons.grid_view_rounded),
            onPressed: () => settings.notesGrid = !settings.notesGrid,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNote(context),
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
          Expanded(
            child: notes.isEmpty
                ? _EmptyNotes(searching: _query.isNotEmpty)
                : _NotesList(notes: notes, grid: settings.notesGrid),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off : Icons.sticky_note_2_outlined,
                size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              searching ? 'Aucune note ne correspond' : 'Aucune note pour le moment',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!searching) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => openNote(context),
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
        onTap: () => openNote(context, note),
        onLongPress: () => _showActions(context),
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
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (note.pinned)
                    Icon(Icons.push_pin, size: 16, color: scheme.primary),
                ],
              ),
              if (note.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(note.body,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium),
              ],
              const SizedBox(height: 10),
              Text(relativeDate(note.updatedAt),
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
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
              leading: Icon(note.pinned ? Icons.push_pin_outlined : Icons.push_pin),
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
