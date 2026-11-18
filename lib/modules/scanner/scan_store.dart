import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../docs/pdf_export.dart' show PdfFonts;
import 'scan_pdf.dart';

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
  int pages;

  /// Text recognised on the pages, used for search.
  String text;

  String get pdf => p.join(dir, 'document.pdf');
  String get ocrFile => p.join(dir, 'ocr.json');
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

  /// Folder holding every scan.
  Future<String> get rootDirectory => _directory();
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
    List<PageOcr>? ocr,
    PdfFonts? fonts,
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
    if (ocr != null) await File(scan.ocrFile).writeAsString(encodeOcr(ocr));
    await _write(scan);
    // A PDF whose text can be searched replaces the picture-only one.
    if (ocr != null && fonts != null) {
      try {
        await rebuildPdf(scan, fonts);
      } on Object {
        // The scanner's own PDF stays.
      }
    }
    await load();
    return scans.firstWhere((s) => s.dir == dir);
  }

  /// What was read on each page, or null for scans made before 1.4.
  Future<List<PageOcr>?> ocrOf(Scan scan) async {
    try {
      final pages = decodeOcr(await File(scan.ocrFile).readAsString());
      return pages.length == scan.pages ? pages : null;
    } on Object {
      return null;
    }
  }

  /// Writes `document.pdf` again from the pages' pictures and text.
  Future<void> rebuildPdf(Scan scan, PdfFonts fonts) async {
    final ocr = await ocrOf(scan);
    final bytes = await buildScanPdf(
      [for (var i = 0; i < scan.pages; i++) ScanPdfPage(scan.page(i), ocr?[i])],
      fonts: fonts,
      title: scan.title,
    );
    final partial = File('${scan.pdf}.part');
    await partial.writeAsBytes(bytes);
    await partial.rename(scan.pdf);
  }

  /// Keeps the pages listed in [order] (indices of the current pages), in
  /// that order: pages left out are deleted. The PDF is built again.
  Future<void> arrangePages(
    Scan scan,
    List<int> order, {
    required PdfFonts fonts,
  }) async {
    if (order.isEmpty ||
        order.toSet().length != order.length ||
        order.any((i) => i < 0 || i >= scan.pages)) {
      throw ArgumentError('Ordre de pages invalide');
    }
    final ocr = await ocrOf(scan);
    // Two steps so that no picture is overwritten while it is still needed.
    for (final i in order) {
      await File(scan.page(i)).rename('${scan.page(i)}.moving');
    }
    for (var i = 0; i < scan.pages; i++) {
      if (!order.contains(i)) {
        final f = File(scan.page(i));
        if (await f.exists()) await f.delete();
      }
    }
    final oldPages = scan.pages;
    final oldPaths = [for (var i = 0; i < oldPages; i++) scan.page(i)];
    scan.pages = order.length;
    for (var n = 0; n < order.length; n++) {
      await File('${oldPaths[order[n]]}.moving').rename(scan.page(n));
    }
    final newOcr = ocr == null ? null : [for (final i in order) ocr[i]];
    if (newOcr != null) {
      await File(scan.ocrFile).writeAsString(encodeOcr(newOcr));
      scan.text = newOcr
          .map((o) => o.text.trim())
          .where((t) => t.isNotEmpty)
          .join('\n');
    }
    await _write(scan);
    await rebuildPdf(scan, fonts);
    notifyListeners();
  }

  /// Turns one page clockwise by [quarterTurns] quarter turns.
  Future<void> rotatePage(
    Scan scan,
    int index,
    int quarterTurns, {
    required PdfFonts fonts,
  }) async {
    final size = await rotateImageFile(scan.page(index), quarterTurns);
    final ocr = await ocrOf(scan);
    if (ocr != null) {
      ocr[index] = rotateOcr(ocr[index], quarterTurns, size.width, size.height);
      await File(scan.ocrFile).writeAsString(encodeOcr(ocr));
    }
    await rebuildPdf(scan, fonts);
    notifyListeners();
  }

  /// Reads the pages again with [read] and stores the result; used for scans
  /// made before pages kept their text positions.
  Future<void> storeOcr(Scan scan, List<PageOcr> ocr, PdfFonts fonts) async {
    await File(scan.ocrFile).writeAsString(encodeOcr(ocr));
    scan.text = ocr
        .map((o) => o.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n');
    await _write(scan);
    await rebuildPdf(scan, fonts);
    notifyListeners();
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
