import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Scan {
  Scan({
    required this.dir,
    required this.title,
    required this.date,
    required this.pages,
    this.text = '',
  });

  /// Folder holding `document.pdf`, `page-N.jpg` and `scan.json`.
  final String dir;
  String title;
  final DateTime date;
  final int pages;

  /// Text recognised on the pages, used for search.
  String text;

  String get pdf => p.join(dir, 'document.pdf');
  String page(int index) => p.join(dir, 'page-${index + 1}.jpg');

  Map<String, Object> toJson() => {
    'title': title,
    'date': date.millisecondsSinceEpoch,
    'pages': pages,
    'text': text,
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Strips a `file://` prefix when a plugin returns a URI.
String localPath(String pathOrUri) => pathOrUri.startsWith('file:')
    ? Uri.parse(pathOrUri).toFilePath()
    : pathOrUri;

/// A title taken from the first meaningful line of the recognised text,
/// or a dated default.
String scanTitle(String text, DateTime date) {
  for (final line in const LineSplitter().convert(text)) {
    final clean = line.trim();
    // Skip noise such as page numbers or stray symbols.
    if (clean.length >= 4 &&
        RegExp(r'\p{L}{3}', unicode: true).hasMatch(clean)) {
      final safe = clean.replaceAll(RegExp(r'[/\\:*?"<>|]'), ' ').trim();
      return safe.length > 40 ? '${safe.substring(0, 40).trim()}…' : safe;
    }
  }
  return 'Scan du ${_two(date.day)}-${_two(date.month)}-${date.year} ${_two(date.hour)}h${_two(date.minute)}';
}

/// Scanned documents, each in its own folder of the app's private storage.
class ScanStore extends ChangeNotifier {
  ScanStore({Future<String> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  static Future<String> _defaultDirectory() async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'scans');

  final Future<String> Function() _directory;
  List<Scan> scans = [];
  bool loaded = false;

  Future<void> load() async {
    final root = Directory(await _directory());
    await root.create(recursive: true);
    final list = <Scan>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      try {
        final meta = jsonDecode(
          await File(p.join(entity.path, 'scan.json')).readAsString(),
        ) as Map<String, dynamic>;
        list.add(
          Scan(
            dir: entity.path,
            title: meta['title'] as String,
            date: DateTime.fromMillisecondsSinceEpoch(meta['date'] as int),
            pages: meta['pages'] as int,
            text: (meta['text'] as String?) ?? '',
          ),
        );
      } on Object {
        continue; // incomplete folder: ignore it
      }
    }
    scans = list..sort((a, b) => b.date.compareTo(a.date));
    loaded = true;
    notifyListeners();
  }

  Future<void> _write(Scan scan) =>
      File(p.join(scan.dir, 'scan.json'))
          .writeAsString(jsonEncode(scan.toJson()));

  /// Copies a finished scan into the library. [images] and [pdf] are the
  /// files produced by the scanner; [text] is what was recognised on them.
  Future<Scan> add({
    required List<String> images,
    required String? pdf,
    required String text,
  }) async {
    final now = DateTime.now();
    final dir = p.join(await _directory(), '${now.microsecondsSinceEpoch}');
    await Directory(dir).create(recursive: true);
    final scan = Scan(
      dir: dir,
      title: scanTitle(text, now),
      date: now,
      pages: images.length,
      text: text,
    );
    for (var i = 0; i < images.length; i++) {
      await File(localPath(images[i])).copy(scan.page(i));
    }
    if (pdf != null) await File(localPath(pdf)).copy(scan.pdf);
    await _write(scan);
    await load();
    return scans.firstWhere((s) => s.dir == dir);
  }

  Future<void> rename(Scan scan, String title) async {
    scan.title = title;
    await _write(scan);
    notifyListeners();
  }

  Future<void> delete(Scan scan) async {
    await Directory(scan.dir).delete(recursive: true);
    await load();
  }

  List<Scan> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return scans;
    return scans
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.text.toLowerCase().contains(q),
        )
        .toList();
  }
}
