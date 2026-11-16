import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/util.dart';
import 'notes_page.dart';
import 'notes_store.dart';

/// Full-screen note editor. Changes are saved automatically.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.note});
  final Note? note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final Note _note = widget.note ?? Note();
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
    _title.dispose();
    _body.dispose();
    super.dispose();
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
