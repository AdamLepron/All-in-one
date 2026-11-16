import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/settings.dart';

/// Above this size only the beginning of the file is shown.
const _maxBytes = 2 * 1024 * 1024;

/// Read-only viewer for plain-text files.
class TextViewPage extends StatefulWidget {
  const TextViewPage({super.key, required this.path});
  final String path;

  @override
  State<TextViewPage> createState() => _TextViewPageState();
}

class _TextViewPageState extends State<TextViewPage> {
  List<String>? _lines;
  bool _truncated = false;
  String? _error;
  bool _wrap = true;

  @override
  void initState() {
    super.initState();
    context.read<AppSettings>().setDocPage(widget.path, 0, notify: false);
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      final length = await file.length();
      final bytes = await file.openRead(0, _maxBytes).expand((b) => b).toList();
      // Files that are not valid UTF-8 are read as Latin-1.
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = latin1.decode(bytes);
      }
      if (!mounted) return;
      setState(() {
        _lines = const LineSplitter().convert(text);
        _truncated = length > _maxBytes;
      });
    } on FileSystemException catch (e) {
      if (mounted) setState(() => _error = e.osError?.message ?? e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final night = settings.readerNight;
    final background = night ? const Color(0xFF121212) : scheme.surface;
    final foreground = night ? const Color(0xFFE0E0E0) : scheme.onSurface;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: settings.readerTextSize,
      height: 1.45,
      color: foreground,
    );
    final lines = _lines;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(
          p.basename(widget.path),
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'Réduire le texte',
            icon: const Icon(Icons.text_decrease),
            onPressed: settings.readerTextSize > 10
                ? () => settings.readerTextSize -= 1
                : null,
          ),
          IconButton(
            tooltip: 'Agrandir le texte',
            icon: const Icon(Icons.text_increase),
            onPressed: settings.readerTextSize < 28
                ? () => settings.readerTextSize += 1
                : null,
          ),
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => settings.readerNight = !night,
                child: Text(night ? 'Mode jour' : 'Mode nuit'),
              ),
              PopupMenuItem(
                value: () => setState(() => _wrap = !_wrap),
                child: Text(
                  _wrap ? 'Lignes longues sur une ligne' : 'Retour à la ligne',
                ),
              ),
              if (lines != null)
                PopupMenuItem(
                  value: () =>
                      Clipboard.setData(ClipboardData(text: lines.join('\n'))),
                  child: const Text('Tout copier'),
                ),
              PopupMenuItem(
                value: () => SharePlus.instance.share(
                  ShareParams(files: [XFile(widget.path)]),
                ),
                child: const Text('Partager'),
              ),
            ],
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                'Lecture impossible\n$_error',
                textAlign: TextAlign.center,
              ),
            )
          : lines == null
          ? const Center(child: CircularProgressIndicator())
          : lines.isEmpty
          ? const Center(child: Text('Ce fichier est vide'))
          : SelectionArea(
              child: Scrollbar(
                interactive: true,
                child: _wrap ? _list(lines, style) : _unwrapped(lines, style),
              ),
            ),
    );
  }

  Widget _list(List<String> lines, TextStyle style) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    itemCount: lines.length + (_truncated ? 1 : 0),
    itemBuilder: (_, i) => i == lines.length
        ? const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('… Fichier volumineux : seul le début est affiché.'),
          )
        // An empty Text has no height: keep blank lines visible.
        : Text(lines[i].isEmpty ? ' ' : lines[i], style: style),
  );

  Widget _unwrapped(List<String> lines, TextStyle style) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          // Wide enough for the longest line at this text size.
          width:
              32 +
              lines.fold<int>(0, (m, l) => l.length > m ? l.length : m) *
                  style.fontSize! *
                  0.62,
          child: _list(lines, style.copyWith(overflow: TextOverflow.visible)),
        ),
      );
}
