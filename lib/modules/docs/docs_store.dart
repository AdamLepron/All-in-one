import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../files/file_ops.dart';

/// Where documents written in the app are saved.
const docsDirectory = '$storageRoot/Documents/All-in-One';

const docExtensions = {'.md', '.txt'};

class DocEntry {
  DocEntry(this.path, this.modified, this.preview);
  final String path;
  final DateTime modified;
  final String preview;

  String get title => p.basenameWithoutExtension(path);
}

String _clean(String line) => line
    .replaceFirst(
      RegExp(r'^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|>\s?)'),
      '',
    )
    .replaceAll(RegExp(r'[*_`~]'), '')
    .trim();

/// First readable line of a document, without Markdown markers. With
/// [title], a first line that was used to name the file is skipped, since
/// the title is already shown.
String previewOf(String text, {String? title}) {
  final lines = [
    for (final line in text.split('\n'))
      if (_clean(line).isNotEmpty) _clean(line),
  ];
  if (lines.isEmpty) return '';
  var line = lines.first;
  if (title != null && lines.length > 1 && titleFor(line) == title) {
    line = lines[1];
  }
  return line.length > 90 ? '${line.substring(0, 90)}…' : line;
}

/// File name for a new document, taken from its first line.
String titleFor(String text) {
  var base = '';
  for (final line in text.split('\n')) {
    base = _clean(line);
    if (base.isNotEmpty) break;
  }
  base = base
      .replaceAll(RegExp(r'[/\\:*?"<>|\n\r]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (base.isEmpty) return 'Document';
  return base.length > 40 ? base.substring(0, 40).trim() : base;
}

/// Documents of [dir], most recently changed first.
Future<List<DocEntry>> listDocuments(String dir) async {
  final directory = Directory(dir);
  if (!await directory.exists()) return [];
  final docs = <DocEntry>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File ||
        !docExtensions.contains(p.extension(entity.path).toLowerCase())) {
      continue;
    }
    try {
      final stat = await entity.stat();
      // Only the start of the file is needed for the preview.
      final head = await entity.openRead(0, 600).expand((b) => b).toList();
      docs.add(
        DocEntry(
          entity.path,
          stat.modified,
          previewOf(
            utf8.decode(head, allowMalformed: true),
            title: p.basenameWithoutExtension(entity.path),
          ),
        ),
      );
    } on FileSystemException {
      continue;
    }
  }
  return docs..sort((a, b) => b.modified.compareTo(a.modified));
}
