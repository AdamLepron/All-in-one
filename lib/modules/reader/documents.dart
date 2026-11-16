import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'pdf_view_page.dart';
import 'text_view_page.dart';

enum DocType { pdf, text, other }

const _textExtensions = {
  'txt',
  'md',
  'csv',
  'json',
  'xml',
  'log',
  'html',
  'htm',
  'yaml',
  'yml',
  'ini',
};

DocType docTypeOf(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (ext == 'pdf') return DocType.pdf;
  if (_textExtensions.contains(ext)) return DocType.text;
  return DocType.other;
}

class DocFile {
  DocFile(this.path, this.size, this.modified);
  final String path;
  final int size;
  final DateTime modified;

  String get name => p.basename(path);
  DocType get type => docTypeOf(path);
}

/// Finds every document under [root], most recently modified first.
/// Hidden folders and the system `Android` folder are skipped.
Future<List<DocFile>> scanDocuments(String root, {int maxDepth = 6}) async {
  final found = <DocFile>[];
  Future<void> walk(String dir, int depth) async {
    try {
      await for (final entity in Directory(dir).list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          if (depth < maxDepth && !(depth == 0 && name == 'Android')) {
            await walk(entity.path, depth + 1);
          }
        } else if (entity is File &&
            kindOfPath(entity.path) == FileKind.document) {
          try {
            final stat = await entity.stat();
            found.add(DocFile(entity.path, stat.size, stat.modified));
          } on FileSystemException {
            continue;
          }
        }
      }
    } on FileSystemException {
      // Unreadable folder: skip it.
    }
  }

  await walk(root, 0);
  return found..sort((a, b) => b.modified.compareTo(a.modified));
}

/// Opens [path] in the built-in reader when the format is supported, and
/// with another installed app otherwise.
Future<void> openDocument(BuildContext context, String path) async {
  switch (docTypeOf(path)) {
    case DocType.pdf:
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => PdfViewPage(path: path)));
    case DocType.text:
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => TextViewPage(path: path)));
    case DocType.other:
      final result = await OpenFilex.open(path);
      if (context.mounted && result.type != ResultType.done) {
        showMessage(
          context,
          result.type == ResultType.noAppToOpen
              ? 'Ce format sera pris en charge dans une prochaine étape'
              : "Impossible d'ouvrir ce fichier",
        );
      }
  }
}
