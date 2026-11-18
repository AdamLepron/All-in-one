import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../docs/pdf_export.dart' show PdfFonts;

/// A line of text read on a page, with its box in image pixels.
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;

  List<Object> toJson() => [text, left, top, right, bottom];

  static OcrLine fromJson(List<dynamic> j) => OcrLine(
    j[0] as String,
    (j[1] as num).toDouble(),
    (j[2] as num).toDouble(),
    (j[3] as num).toDouble(),
    (j[4] as num).toDouble(),
  );
}

/// What was read on one page: image size and lines.
class PageOcr {
  const PageOcr(this.width, this.height, this.lines);
  final int width;
  final int height;
  final List<OcrLine> lines;

  String get text => lines.map((l) => l.text).join('\n');

  Map<String, Object> toJson() => {
    'w': width,
    'h': height,
    'lines': [for (final l in lines) l.toJson()],
  };

  static PageOcr fromJson(Map<String, dynamic> j) => PageOcr(
    j['w'] as int,
    j['h'] as int,
    [for (final l in j['lines'] as List) OcrLine.fromJson(l as List<dynamic>)],
  );
}

List<PageOcr> decodeOcr(String json) => [
  for (final p in jsonDecode(json) as List)
    PageOcr.fromJson(p as Map<String, dynamic>),
];

String encodeOcr(List<PageOcr> pages) =>
    jsonEncode([for (final p in pages) p.toJson()]);

/// One page of a scan for the PDF: its image and what was read on it
/// (null when nothing was recognised).
class ScanPdfPage {
  const ScanPdfPage(this.imagePath, this.ocr);
  final String imagePath;
  final PageOcr? ocr;
}

/// Width of every PDF page, in points (A4 portrait).
const _pageWidth = 595.0;

/// A PDF of the scanned [pages]: each page is its picture, with the
/// recognised text laid invisibly over it, so the PDF can be searched and
/// its text copied.
Future<Uint8List> buildScanPdf(
  List<ScanPdfPage> pages, {
  required PdfFonts fonts,
  String title = 'Scan',
  bool compress = true,
}) async {
  final doc = pw.Document(
    compress: compress,
    title: title,
    creator: 'All-in-One',
    theme: pw.ThemeData.withFont(base: fonts.regular),
  );
  for (final page in pages) {
    final bytes = await File(page.imagePath).readAsBytes();
    final image = pw.MemoryImage(bytes);
    final ocr = page.ocr;
    // The page takes the picture's proportions.
    final w = (ocr?.width ?? image.width ?? 1000).toDouble();
    final h = (ocr?.height ?? image.height ?? 1400).toDouble();
    final scale = _pageWidth / w;
    final pageHeight = h * scale;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(_pageWidth, pageHeight),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
            if (ocr != null)
              for (final line in ocr.lines)
                if (line.text.trim().isNotEmpty)
                  pw.Positioned(
                    left: line.left * scale,
                    top: line.top * scale,
                    // Drawn straight on the canvas: the text style of the
                    // widgets does not carry the invisible mode through.
                    child: pw.Builder(
                      builder: (context) {
                        final font = fonts.regular.getFont(context);
                        final height = (line.bottom - line.top) * scale;
                        final size = (height * 0.8).clamp(3.0, 80.0);
                        return pw.CustomPaint(
                          size: PdfPoint(
                            (line.right - line.left) * scale,
                            height,
                          ),
                          painter: (canvas, box) => canvas.drawString(
                            font,
                            size,
                            line.text,
                            0,
                            height * 0.2,
                            mode: PdfTextRenderingMode.invisible,
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Turns the picture at [path] by [quarterTurns] quarter turns clockwise
/// and saves it back, returning the new size.
Future<({int width, int height})> rotateImageFile(
  String path,
  int quarterTurns,
) => Isolate.run(() {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('Image illisible');
  final turned = img.copyRotate(decoded, angle: 90.0 * (quarterTurns % 4));
  File(path).writeAsBytesSync(img.encodeJpg(turned, quality: 92));
  return (width: turned.width, height: turned.height);
});

/// [ocr] after the page was turned [quarterTurns] clockwise: the picture
/// is now [newWidth] × [newHeight], and every line moves with it.
PageOcr rotateOcr(PageOcr ocr, int quarterTurns, int newWidth, int newHeight) {
  final turns = quarterTurns % 4;
  if (turns == 0) return ocr;
  final lines = <OcrLine>[];
  for (final l in ocr.lines) {
    var left = l.left, top = l.top, right = l.right, bottom = l.bottom;
    var w = ocr.width.toDouble(), h = ocr.height.toDouble();
    for (var i = 0; i < turns; i++) {
      // One clockwise quarter turn: (x, y) → (h − y, x).
      final nl = h - bottom, nt = left, nr = h - top, nb = right;
      left = nl;
      top = nt;
      right = nr;
      bottom = nb;
      final t = w;
      w = h;
      h = t;
    }
    lines.add(OcrLine(l.text, left, top, right, bottom));
  }
  return PageOcr(newWidth, newHeight, lines);
}
