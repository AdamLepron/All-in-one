import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/util.dart';
import '../docs/markdown_edit.dart';
import 'note_files.dart';
import 'notes_page.dart';
import 'notes_store.dart';

/// Full-screen note editor. Changes are saved automatically.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.note, this.folder = ''});
  final Note? note;

  /// Folder given to a new note.
  final String folder;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final Note _note = widget.note ?? Note(folder: widget.folder);
  late final _history = TextHistory(_body);
  final _focus = FocusNode();
  late final _title = TextEditingController(text: _note.title);
  late final _body = TextEditingController(text: _note.body);
  late final NotesStore _store;
  Timer? _debounce;
  bool _dirty = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    // Resolved now: the context can no longer be used in dispose().
    _store = context.read<NotesStore>();
  }

  void _onChanged() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _save);
    setState(() {});
  }

  Future<void> _save() async {
    _debounce?.cancel();
    if (!_dirty || _deleted) return;
    _dirty = false;
    _note
      ..title = _title.text.trim()
      ..body = _body.text;
    await _store.save(_note);
  }

  @override
  void dispose() {
    _save();
    _history.dispose();
    _focus.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Applies a formatting edit to the body as a step of its own.
  void _format(TextEditingValue Function(TextEditingValue) edit) {
    _history.checkpoint();
    _body.value = edit(_body.value);
    _history.checkpoint();
    _focus.requestFocus();
    _onChanged();
  }

  Future<void> _attach() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles();
    } on Object {
      return;
    }
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      final name = await NoteFiles.add(path);
      _note.attachments.add(name);
    }
    if (mounted) _onChanged();
  }

  Future<void> _removeAttachment(String name) async {
    setState(() => _note.attachments.remove(name));
    _dirty = true;
    await _save();
    // The file goes only once the note no longer refers to it.
    await NoteFiles.remove([name]);
  }

  Future<void> _openAttachment(String name) async {
    final file = await NoteFiles.file(name);
    if (!mounted) return;
    if (NoteFiles.isImage(name)) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              InteractiveViewer(child: Center(child: Image.file(file))),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: 'Fermer',
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(dialog),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final r = await OpenFilex.open(file.path);
      if (mounted && r.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucune application ne peut ouvrir ce fichier'),
          ),
        );
      }
    }
  }

  Future<void> _chooseFolder() async {
    final store = _store;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Dossier')),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Aucun dossier'),
                selected: _note.folder.isEmpty,
                onTap: () => Navigator.pop(sheet, ''),
              ),
              for (final f in store.folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f),
                  selected: _note.folder == f,
                  onTap: () => Navigator.pop(sheet, f),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Nouveau dossier…'),
                onTap: () async {
                  final name = await askNoteFolder(context);
                  if (sheet.mounted) Navigator.pop(sheet, name?.trim());
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    _note.folder = choice;
    _onChanged();
  }

  int get _wordCount => _body.text.trim().isEmpty
      ? 0
      : _body.text.trim().split(RegExp(r'\s+')).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final background = noteBackground(context, _note.color);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            tooltip: _note.pinned ? 'Désépingler' : 'Épingler',
            icon: Icon(_note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () {
              _note.pinned = !_note.pinned;
              _onChanged();
            },
          ),
          IconButton(
            tooltip: _note.folder.isEmpty
                ? 'Dossier'
                : 'Dossier : ${_note.folder}',
            icon: Icon(
              _note.folder.isEmpty
                  ? Icons.folder_open_outlined
                  : Icons.folder_rounded,
            ),
            onPressed: _chooseFolder,
          ),
          IconButton(
            tooltip: 'Joindre un fichier',
            icon: const Icon(Icons.attach_file),
            onPressed: _attach,
          ),
          IconButton(
            tooltip: 'Couleur',
            icon: const Icon(Icons.palette_outlined),
            onPressed: _pickColor,
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              _deleted = true;
              _debounce?.cancel();
              final navigator = Navigator.of(context);
              if (_note.id != null) deleteNoteWithUndo(context, _note);
              navigator.pop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  TextField(
                    controller: _title,
                    onChanged: (_) => _onChanged(),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLines: null,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Titre',
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _body,
                    focusNode: _focus,
                    inputFormatters: [ListContinuation()],
                    onChanged: (_) => _onChanged(),
                    autofocus: widget.note == null,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    minLines: 12,
                    style: text.bodyLarge?.copyWith(height: 1.5),
                    decoration: const InputDecoration(
                      hintText: 'Commencez à écrire…',
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (_note.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in _note.attachments)
                          _AttachmentChip(
                            name: name,
                            onOpen: () => _openAttachment(name),
                            onRemove: () => _removeAttachment(name),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Formatting toolbar.
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _tool(
                    Icons.undo,
                    'Annuler',
                    _history.canUndo ? () => setState(_history.undo) : null,
                  ),
                  _tool(
                    Icons.redo,
                    'Rétablir',
                    _history.canRedo ? () => setState(_history.redo) : null,
                  ),
                  _tool(
                    Icons.check_box_outlined,
                    'Liste à cocher',
                    () => _format(toggleChecklist),
                  ),
                  _tool(
                    Icons.format_list_bulleted,
                    'Liste à puces',
                    () => _format(toggleBullets),
                  ),
                  _tool(
                    Icons.format_bold,
                    'Gras',
                    () => _format((v) => toggleWrap(v, '**')),
                  ),
                  _tool(
                    Icons.format_italic,
                    'Italique',
                    () => _format((v) => toggleWrap(v, '*')),
                  ),
                  _tool(
                    Icons.title_rounded,
                    'Titre',
                    () => _format(cycleHeading),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Modifiée ${relativeDate(_note.updatedAt).toLowerCase()}',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$_wordCount mot${_wordCount > 1 ? 's' : ''} · ${_body.text.length} caractères',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback? onTap) =>
      IconButton(tooltip: label, icon: Icon(icon), onPressed: onTap);

  void _pickColor() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < noteColors.length; i++)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    Navigator.pop(sheet);
                    _note.color = i;
                    _onChanged();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: noteBackground(context, i),
                      border: Border.all(
                        width: _note.color == i ? 3 : 1,
                        color: _note.color == i
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: i == 0
                        ? const Icon(
                            Icons.format_color_reset_outlined,
                            size: 18,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.name,
    required this.onOpen,
    required this.onRemove,
  });
  final String name;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(
        NoteFiles.isImage(name)
            ? Icons.image_outlined
            : Icons.description_outlined,
        size: 18,
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      onPressed: onOpen,
      deleteIcon: const Icon(Icons.close, size: 18),
      deleteButtonTooltipMessage: 'Retirer la pièce jointe',
      onDeleted: onRemove,
    );
  }
}
