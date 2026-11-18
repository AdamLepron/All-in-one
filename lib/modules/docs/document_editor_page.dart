import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'docs_store.dart';
import 'find_replace.dart';
import 'markdown.dart';
import 'markdown_edit.dart';
import 'markdown_view.dart';
import 'pdf_export.dart';

/// Text and Markdown editor. Changes are saved automatically, a new
/// document gets its file name from its first line.
class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage({
    super.key,
    this.path,
    this.directory = docsDirectory,
    this.fonts,
    this.initialText,
  });

  /// Text a new document starts with, for example shared from another app.
  final String? initialText;

  /// Existing document, or null to write a new one.
  final String? path;
  final String directory;

  /// Fonts for PDF export; the bundled ones when null.
  final PdfFonts? fonts;

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  final _text = TextEditingController();
  late final TextHistory _history = TextHistory(_text);
  final _focus = FocusNode();
  Timer? _saveTimer;
  String? _path;
  bool _loaded = false;
  bool _dirty = false;
  bool _preview = false;
  bool _exporting = false;

  // Search and replace.
  bool _finding = false;
  final _findText = TextEditingController();
  final _replaceText = TextEditingController();
  bool _caseSensitive = false;
  bool _wholeWord = false;
  List<TextMatch> _matches = const [];
  int _current = -1;

  /// Bumped on each keystroke batch so word counts do not rebuild per key.
  ({int words, int characters}) _stats = (words: 0, characters: 0);

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _text.addListener(_onChanged);
    _load();
  }

  Future<void> _load() async {
    final path = _path;
    if (path != null) {
      try {
        _text.text = await File(path).readAsString();
      } on Object {
        if (mounted) showMessage(context, 'Impossible de lire ce document');
      }
    }
    if (!mounted) return;
    // A new document may start with text received from another app.
    final starting = path == null ? widget.initialText : null;
    if (starting != null) _text.text = starting;
    _dirty = starting != null;
    _lastText = _text.text;
    _history.reset();
    setState(() {
      _loaded = true;
      _stats = textStats(_text.text);
    });
    if (starting != null) _save(); // keep the received text right away
    if (path == null) _focus.requestFocus();
  }

  String _lastText = '';
  void _onChanged() {
    if (!_loaded || _text.text == _lastText) return;
    _lastText = _text.text;
    if (_finding) _search(keepPosition: true);
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), () {
      _save();
      // Refreshes the "Enregistré" indicator.
      if (mounted) setState(() {});
    });
    setState(() => _stats = textStats(_text.text));
  }

  /// Writes the document. A new one is created on first non-empty save.
  void _save() {
    _saveTimer?.cancel();
    if (!_dirty) return;
    final text = _text.text;
    try {
      if (_path == null) {
        if (text.trim().isEmpty) return;
        Directory(widget.directory).createSync(recursive: true);
        final name = titleFor(text);
        var target = p.join(widget.directory, '$name.md');
        for (var i = 1; File(target).existsSync(); i++) {
          target = p.join(widget.directory, '$name ($i).md');
        }
        _path = target;
      }
      File(_path!).writeAsStringSync(text);
      _dirty = false;
    } on FileSystemException {
      if (mounted) showMessage(context, "L'enregistrement a échoué");
    }
  }

  @override
  void dispose() {
    _save();
    final path = _path;
    if (path != null) MediaChannel.scan([path]);
    _saveTimer?.cancel();
    _findText.dispose();
    _replaceText.dispose();
    _text.dispose();
    _history.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _name =>
      _path == null ? 'Nouveau document' : p.basenameWithoutExtension(_path!);

  void _apply(TextEditingValue Function(TextEditingValue) edit) {
    _history.checkpoint(); // formatting is a step of its own
    _text.value = edit(_text.value);
    _history.checkpoint();
    _focus.requestFocus();
  }

  /// Looks for the query again; selects the match at or after the caret.
  void _search({bool keepPosition = false}) {
    final found = findAll(
      _text.text,
      _findText.text,
      caseSensitive: _caseSensitive,
      wholeWord: _wholeWord,
    );
    final caret = _text.selection.isValid ? _text.selection.start : 0;
    setState(() {
      _matches = found;
      _current = found.isEmpty
          ? -1
          : keepPosition && _current >= 0 && _current < found.length
          ? _current
          : nextMatchIndex(found, caret);
    });
  }

  void _go({bool backwards = false}) {
    if (_matches.isEmpty) return;
    final caret = _text.selection.isValid
        ? (backwards ? _text.selection.start : _text.selection.end)
        : 0;
    final i = nextMatchIndex(_matches, caret, backwards: backwards);
    final m = _matches[i];
    setState(() => _current = i);
    // Focus makes the field show and scroll to the selection.
    _focus.requestFocus();
    _text.selection = TextSelection(baseOffset: m.start, extentOffset: m.end);
  }

  void _replaceCurrent() {
    if (_current < 0 || _current >= _matches.length) return;
    final m = _matches[_current];
    _history.checkpoint();
    final text = replaceMatch(_text.text, m, _replaceText.text);
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: m.start + _replaceText.text.length,
      ),
    );
    _history.checkpoint();
    _search();
    _go();
  }

  void _replaceAll() {
    final r = replaceEvery(
      _text.text,
      _findText.text,
      _replaceText.text,
      caseSensitive: _caseSensitive,
      wholeWord: _wholeWord,
    );
    if (r.count == 0) return;
    _history.checkpoint();
    _text.value = TextEditingValue(
      text: r.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _history.checkpoint();
    _search();
    showMessage(
      context,
      '${r.count} remplacement${r.count > 1 ? 's' : ''}',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => setState(_history.undo),
      ),
    );
  }

  Future<void> _addImage() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile();
    } on Object {
      return;
    }
    final source = picked?.path;
    if (source == null || !mounted) return;
    try {
      final dir = _path == null ? widget.directory : p.dirname(_path!);
      final images = Directory(p.join(dir, 'images'));
      await images.create(recursive: true);
      final target = await uniquePath(images.path, p.basename(source));
      await File(source).copy(target);
      _apply(
        (v) => insertImage(
          v,
          p.basenameWithoutExtension(source),
          'images/${p.basename(target)}',
        ),
      );
    } on FileSystemException {
      if (mounted) showMessage(context, "Impossible d'ajouter l'image");
    }
  }

  Future<void> _addTable() async {
    var columns = 3, rows = 2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setLocal) {
          Widget stepper(
            String label,
            int value,
            int min,
            int max,
            void Function(int) set,
          ) => Row(
            children: [
              Expanded(child: Text(label)),
              IconButton(
                tooltip: 'Moins de $label',
                icon: const Icon(Icons.remove),
                onPressed: value > min
                    ? () => setLocal(() => set(value - 1))
                    : null,
              ),
              SizedBox(width: 28, child: Center(child: Text('$value'))),
              IconButton(
                tooltip: 'Plus de $label',
                icon: const Icon(Icons.add),
                onPressed: value < max
                    ? () => setLocal(() => set(value + 1))
                    : null,
              ),
            ],
          );
          return AlertDialog(
            title: const Text('Insérer un tableau'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                stepper('colonnes', columns, 1, 6, (v) => columns = v),
                stepper('lignes', rows, 1, 12, (v) => rows = v),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Insérer'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      _apply((v) => insertTable(v, columns: columns, rows: rows));
    }
  }

  Future<void> _link() async {
    final controller = TextEditingController(text: 'https://');
    final url = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Adresse du lien'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Insérer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url != null && url.trim().isNotEmpty && url.trim() != 'https://') {
      _apply((v) => insertLink(v, url.trim()));
    }
  }

  Future<void> _rename() async {
    _save();
    final path = _path;
    if (path == null) return;
    final name = await askName(
      context,
      title: 'Renommer',
      initial: _name,
      action: 'Renommer',
    );
    if (name == null || !mounted) return;
    try {
      final next = await renameEntity(path, '$name${p.extension(path)}');
      setState(() => _path = next);
    } on FileSystemException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _exportPdf() async {
    _save();
    if (_text.text.trim().isEmpty) {
      showMessage(context, 'Le document est vide');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final fonts = widget.fonts ?? await PdfFonts.load();
      final bytes = await markdownToPdf(
        _text.text,
        title: _name,
        fonts: fonts,
        baseDir: _path == null ? widget.directory : p.dirname(_path!),
      );
      final dir = _path == null ? widget.directory : p.dirname(_path!);
      await Directory(dir).create(recursive: true);
      final target = await uniquePath(dir, '$_name.pdf');
      await File(target).writeAsBytes(bytes);
      unawaited(MediaChannel.scan([target]));
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('PDF enregistré : ${p.basename(target)}'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Partager',
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(files: [XFile(target)])),
            ),
          ),
        );
    } on Object {
      if (mounted) showMessage(context, "L'export a échoué");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final path = _path;
    final navigator = Navigator.of(context);
    if (path != null) {
      _saveTimer?.cancel();
      _dirty = false;
      try {
        await Trash.device().put(path);
      } on Object {
        await File(path).delete();
      }
    }
    navigator.pop();
  }

  Widget _findBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findText,
                    autofocus: true,
                    onChanged: (_) => _search(),
                    onSubmitted: (_) => _go(),
                    decoration: InputDecoration(
                      hintText: 'Rechercher',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      suffixText: _findText.text.isEmpty
                          ? null
                          : _matches.isEmpty
                          ? '0'
                          : '${_current + 1}/${_matches.length}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Résultat précédent',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: _matches.isEmpty
                      ? null
                      : () => _go(backwards: true),
                ),
                IconButton(
                  tooltip: 'Résultat suivant',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _matches.isEmpty ? null : _go,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceText,
                    decoration: const InputDecoration(
                      hintText: 'Remplacer par',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _current < 0 ? null : _replaceCurrent,
                  child: const Text('Remplacer'),
                ),
                TextButton(
                  onPressed: _matches.isEmpty ? null : _replaceAll,
                  child: const Text('Tout'),
                ),
              ],
            ),
            Row(
              children: [
                FilterChip(
                  label: const Text('Aa'),
                  tooltip: 'Respecter la casse',
                  selected: _caseSensitive,
                  onSelected: (v) {
                    _caseSensitive = v;
                    _search();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Mot entier'),
                  selected: _wholeWord,
                  onSelected: (v) {
                    _wholeWord = v;
                    _search();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final minutes = (_stats.words / 220).ceil();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _path == null ? null : _rename,
          child: Text(
            _name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _preview ? 'Modifier' : 'Aperçu',
            icon: Icon(
              _preview ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
            onPressed: () {
              _save();
              setState(() => _preview = !_preview);
              if (!_preview) _focus.requestFocus();
            },
          ),
          if (!_preview)
            IconButton(
              tooltip: 'Rechercher et remplacer',
              icon: Icon(_finding ? Icons.search_off : Icons.search),
              onPressed: () {
                setState(() => _finding = !_finding);
                if (_finding) {
                  _search();
                } else {
                  _matches = const [];
                  _current = -1;
                }
              },
            ),
          IconButton(
            tooltip: 'Exporter en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exporting ? null : _exportPdf,
          ),
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              if (_path != null)
                PopupMenuItem(value: _rename, child: const Text('Renommer')),
              PopupMenuItem(
                value: () {
                  _save();
                  if (_path != null) {
                    SharePlus.instance.share(
                      ShareParams(files: [XFile(_path!)]),
                    );
                  } else {
                    SharePlus.instance.share(ShareParams(text: _text.text));
                  }
                },
                child: const Text('Partager'),
              ),
              PopupMenuItem(
                value: () {
                  Clipboard.setData(ClipboardData(text: _text.text));
                  showMessage(context, 'Texte copié');
                },
                child: const Text('Tout copier'),
              ),
              PopupMenuItem(value: _delete, child: const Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_exporting) const LinearProgressIndicator(minHeight: 2),
                if (_finding && !_preview) _findBar(context),
                Expanded(
                  child: _preview
                      ? MarkdownView(
                          _text.text,
                          baseDir: _path == null
                              ? widget.directory
                              : p.dirname(_path!),
                        )
                      : TextField(
                          controller: _text,
                          focusNode: _focus,
                          inputFormatters: [ListContinuation()],
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: text.bodyLarge?.copyWith(height: 1.5),
                          decoration: const InputDecoration(
                            hintText:
                                'Écrivez ici…  (# titre, - liste, **gras**)',
                            filled: false,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.fromLTRB(20, 12, 20, 12),
                          ),
                        ),
                ),
                Material(
                  color: scheme.surfaceContainer,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_preview)
                          SizedBox(
                            height: 46,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              children: [
                                _Tool(
                                  Icons.undo_rounded,
                                  'Annuler',
                                  () => setState(_history.undo),
                                ),
                                _Tool(
                                  Icons.redo_rounded,
                                  'Rétablir',
                                  () => setState(_history.redo),
                                ),
                                _Tool(
                                  Icons.title_rounded,
                                  'Titre',
                                  () => _apply(cycleHeading),
                                ),
                                _Tool(
                                  Icons.format_bold_rounded,
                                  'Gras',
                                  () => _apply((v) => toggleWrap(v, '**')),
                                ),
                                _Tool(
                                  Icons.format_italic_rounded,
                                  'Italique',
                                  () => _apply((v) => toggleWrap(v, '*')),
                                ),
                                _Tool(
                                  Icons.strikethrough_s_rounded,
                                  'Barré',
                                  () => _apply((v) => toggleWrap(v, '~~')),
                                ),
                                _Tool(
                                  Icons.format_list_bulleted_rounded,
                                  'Liste à puces',
                                  () => _apply(toggleBullets),
                                ),
                                _Tool(
                                  Icons.format_list_numbered_rounded,
                                  'Liste numérotée',
                                  () => _apply(toggleNumbers),
                                ),
                                _Tool(
                                  Icons.checklist_rounded,
                                  'Cases à cocher',
                                  () => _apply(toggleChecklist),
                                ),
                                _Tool(
                                  Icons.format_quote_rounded,
                                  'Citation',
                                  () => _apply(toggleQuote),
                                ),
                                _Tool(
                                  Icons.code_rounded,
                                  'Code',
                                  () => _apply((v) => toggleWrap(v, '`')),
                                ),
                                _Tool(Icons.link_rounded, 'Lien', _link),
                                _Tool(
                                  Icons.image_outlined,
                                  'Insérer une image',
                                  _addImage,
                                ),
                                _Tool(
                                  Icons.table_chart_outlined,
                                  'Insérer un tableau',
                                  _addTable,
                                ),
                                _Tool(
                                  Icons.horizontal_rule_rounded,
                                  'Séparateur',
                                  () => _apply(insertRule),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                          child: Row(
                            children: [
                              Text(
                                '${_stats.words} mot${_stats.words > 1 ? 's' : ''} · ${_stats.characters} caractères${_stats.words > 0 ? ' · $minutes min de lecture' : ''}',
                                style: text.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _dirty
                                    ? 'Modifications en cours…'
                                    : 'Enregistré',
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
                ),
              ],
            ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool(this.icon, this.tooltip, this.onPressed);
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed);
}
