import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'docs_store.dart';
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
  });

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
    _dirty = false;
    _lastText = _text.text;
    _history.reset();
    setState(() {
      _loaded = true;
      _stats = textStats(_text.text);
    });
    if (path == null) _focus.requestFocus();
  }

  String _lastText = '';
  void _onChanged() {
    if (!_loaded || _text.text == _lastText) return;
    _lastText = _text.text;
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
      final bytes = await markdownToPdf(_text.text, title: _name, fonts: fonts);
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
                Expanded(
                  child: _preview
                      ? MarkdownView(_text.text)
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
