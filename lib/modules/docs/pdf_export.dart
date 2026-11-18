import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'markdown.dart';

/// Fonts embedded in exported PDFs: the built-in PDF fonts cannot draw
/// characters such as œ, € or typographic quotes.
class PdfFonts {
  PdfFonts(this.regular, this.bold, this.italic, this.boldItalic);
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  static Future<PdfFonts> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    Future<pw.Font> font(String name) async =>
        pw.Font.ttf(await b.load('assets/fonts/$name.ttf'));
    return PdfFonts(
      await font('Roboto-Regular'),
      await font('Roboto-Bold'),
      await font('Roboto-Italic'),
      await font('Roboto-BoldItalic'),
    );
  }
}

const _ink = PdfColor.fromInt(0xFF1C1C22);
const _muted = PdfColor.fromInt(0xFF6B6B78);
const _linkColor = PdfColor.fromInt(0xFF0A5BD6);

/// Renders Markdown [source] as an A4 PDF.
Future<Uint8List> markdownToPdf(
  String source, {
  required String title,
  required PdfFonts fonts,
  String? baseDir,
}) async {
  final doc = pw.Document(
    title: title,
    creator: 'All-in-One',
    theme: pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
      italic: fonts.italic,
      boldItalic: fonts.boldItalic,
    ),
  );

  pw.TextSpan spans(
    String text, {
    double size = 11.5,
    bool bold = false,
    bool italic = false,
  }) {
    return pw.TextSpan(
      children: [
        for (final s in parseInline(text))
          pw.TextSpan(
            text: s.text,
            annotation: s.link == null ? null : pw.AnnotationUrl(s.link!),
            style: pw.TextStyle(
              fontSize: s.code ? size - 1 : size,
              color: s.link != null ? _linkColor : _ink,
              fontWeight: bold || s.bold
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              fontStyle: italic || s.italic
                  ? pw.FontStyle.italic
                  : pw.FontStyle.normal,
              decoration: s.strike
                  ? pw.TextDecoration.lineThrough
                  : s.link != null
                  ? pw.TextDecoration.underline
                  : null,
              background: s.code
                  ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDEDF2))
                  : null,
            ),
          ),
      ],
    );
  }

  // Pictures are read up front: building a page cannot wait for the disk.
  final images = <String, pw.MemoryImage>{};
  for (final b in parseMarkdown(source)) {
    if (b is! ImageBlock || images.containsKey(b.src)) continue;
    final file = resolveImage(b.src, baseDir);
    if (file == null || file.lengthSync() > 12 * 1024 * 1024) continue;
    try {
      images[b.src] = pw.MemoryImage(await file.readAsBytes());
    } on Object {
      // Unreadable picture: shown as its description.
    }
  }

  pw.Widget render(Block b) {
    switch (b) {
      case Heading():
        final size = const [0.0, 22.0, 17.0, 14.0][b.level];
        return pw.Padding(
          padding: pw.EdgeInsets.only(top: b.level == 1 ? 10 : 6, bottom: 5),
          child: pw.RichText(text: spans(b.text, size: size, bold: true)),
        );
      case Paragraph():
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.RichText(text: spans(b.text), softWrap: true),
        );
      case ListItem():
        final marker = b.checked != null
            ? pw.Container(
                width: 9,
                height: 9,
                margin: const pw.EdgeInsets.only(top: 3, right: 6),
                decoration: pw.BoxDecoration(
                  color: b.checked! ? _ink : null,
                  border: pw.Border.all(color: _ink, width: 1),
                ),
              )
            : pw.SizedBox(
                width: b.number != null ? 22 : 14,
                child: pw.Text(
                  b.number != null ? '${b.number}.' : '•',
                  style: const pw.TextStyle(fontSize: 11.5),
                ),
              );
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: 6.0 + b.indent * 16, bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              marker,
              pw.Expanded(
                child: pw.RichText(
                  text: spans(b.text).copyWith(
                    style: pw.TextStyle(
                      decoration: b.checked == true
                          ? pw.TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case Quote():
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8, left: 2),
          padding: const pw.EdgeInsets.only(left: 10, top: 2, bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: _muted, width: 2.5)),
          ),
          child: pw.RichText(text: spans(b.text, italic: true)),
        );
      case CodeBlock():
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFEDEDF2),
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            b.code,
            style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2),
          ),
        );
      case Rule():
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: _muted, thickness: 0.8),
        );
      case ImageBlock():
        final image = images[b.src];
        if (image == null) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Text(
              '[${b.alt.isEmpty ? 'image' : b.alt}]',
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
          );
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Center(
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxHeight: 420),
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
      case TableBlock():
        pw.Alignment align(int c) => switch (b.aligns[c]) {
          CellAlign.left => pw.Alignment.centerLeft,
          CellAlign.center => pw.Alignment.center,
          CellAlign.right => pw.Alignment.centerRight,
        };
        pw.Widget cell(String t, int c, {bool head = false}) => pw.Container(
          alignment: align(c),
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          color: head ? const PdfColor.fromInt(0xFFEDEDF2) : null,
          child: pw.RichText(text: spans(t, size: 10.5, bold: head)),
        );
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 9),
          child: pw.Table(
            border: pw.TableBorder.all(color: _muted, width: 0.6),
            children: [
              pw.TableRow(
                children: [
                  for (var c = 0; c < b.header.length; c++)
                    cell(b.header[c], c, head: true),
                ],
              ),
              for (final row in b.rows)
                pw.TableRow(
                  children: [
                    for (var c = 0; c < row.length; c++) cell(row[c], c),
                  ],
                ),
            ],
          ),
        );
    }
  }

  final blocks = parseMarkdown(source);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(52, 52, 52, 56),
      maxPages: 1000,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ),
      build: (_) => blocks.isEmpty
          ? [pw.SizedBox()]
          : [for (final b in blocks) render(b)],
    ),
  );
  return doc.save();
}
