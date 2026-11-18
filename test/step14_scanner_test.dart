import 'dart:io';
import 'dart:typed_data';

import 'package:all_in_one/modules/docs/pdf_export.dart';
import 'package:all_in_one/modules/scanner/scan_pdf.dart';
import 'package:all_in_one/modules/scanner/scan_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late PdfFonts fonts;

  Future<PdfFonts> loadFonts() async {
    Future<pw.Font> f(String n) async => pw.Font.ttf(
      ByteData.sublistView(await File('assets/fonts/$n.ttf').readAsBytes()),
    );
    return PdfFonts(
      await f('Roboto-Regular'),
      await f('Roboto-Bold'),
      await f('Roboto-Italic'),
      await f('Roboto-BoldItalic'),
    );
  }

  String jpg(String name, int w, int h, {int shade = 200}) {
    final image = img.Image(width: w, height: h)
      ..clear(img.ColorRgb8(shade, shade, shade));
    final path = '${tmp.path}/$name';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(image));
    return path;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('step14_scan');
    fonts = await loadFonts();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  int pageCount(List<int> bytes) => int.parse(
    RegExp(r'/Count (\d+)').firstMatch(String.fromCharCodes(bytes))!.group(1)!,
  );

  test('OCR data round-trips through JSON', () {
    final pages = [
      const PageOcr(100, 200, [OcrLine('Bonjour', 1, 2, 30, 12)]),
      const PageOcr(50, 50, []),
    ];
    final back = decodeOcr(encodeOcr(pages));
    expect(back, hasLength(2));
    expect(back.first.lines.single.text, 'Bonjour');
    expect(back.first.lines.single.right, 30);
    expect(back.first.text, 'Bonjour');
    expect(back.last.lines, isEmpty);
  });

  test('a scan PDF has one page per picture and invisible text', () async {
    final a = jpg('a.jpg', 300, 400);
    final b = jpg('b.jpg', 400, 300);
    final bytes = await buildScanPdf(
      [
        ScanPdfPage(
          a,
          const PageOcr(300, 400, [
            OcrLine('Facture électricité', 20, 30, 200, 50),
          ]),
        ),
        ScanPdfPage(b, null),
      ],
      fonts: fonts,
      compress: false,
    );
    final text = String.fromCharCodes(bytes);
    expect(text.startsWith('%PDF'), isTrue);
    expect(pageCount(bytes), 2);
    // Text render mode 3: drawn nowhere, but still selectable and searchable.
    expect(text.contains('3 Tr'), isTrue);
  });

  test('a PDF without any recognised text has no text layer', () async {
    final bytes = await buildScanPdf(
      [ScanPdfPage(jpg('a.jpg', 100, 100), null)],
      fonts: fonts,
      compress: false,
    );
    expect(String.fromCharCodes(bytes).contains('3 Tr'), isFalse);
  });

  test('turning the text boxes with the page', () {
    const ocr = PageOcr(100, 200, [OcrLine('x', 10, 20, 30, 40)]);
    // One clockwise turn of a 100×200 picture gives 200×100.
    final r = rotateOcr(ocr, 1, 200, 100);
    final l = r.lines.single;
    expect((r.width, r.height), (200, 100));
    expect((l.left, l.top, l.right, l.bottom), (160, 10, 180, 30));
    // Four turns bring it back; zero turns change nothing.
    var back = ocr;
    var w = 100, h = 200;
    for (var i = 0; i < 4; i++) {
      back = rotateOcr(back, 1, h, w);
      final t = w;
      w = h;
      h = t;
    }
    final b = back.lines.single;
    expect((b.left, b.top, b.right, b.bottom), (10, 20, 30, 40));
    expect(rotateOcr(ocr, 4, 100, 200), same(ocr));
  });

  test('a picture is turned on disk', () async {
    final path = jpg('r.jpg', 80, 40);
    final size = await rotateImageFile(path, 1);
    expect((size.width, size.height), (40, 80));
    final decoded = img.decodeJpg(File(path).readAsBytesSync())!;
    expect((decoded.width, decoded.height), (40, 80));
  });

  group('scan store', () {
    late ScanStore store;
    late Scan scan;

    setUp(() async {
      store = ScanStore(directory: () async => '${tmp.path}/scans');
      final images = [
        jpg('src/1.jpg', 100, 140, shade: 10),
        jpg('src/2.jpg', 100, 140, shade: 100),
        jpg('src/3.jpg', 100, 140, shade: 200),
      ];
      scan = await store.add(
        images: images,
        pdf: null,
        text: 'un\ndeux\ntrois',
        ocr: [
          for (final t in ['un', 'deux', 'trois'])
            PageOcr(100, 140, [OcrLine(t, 5, 5, 50, 20)]),
        ],
        fonts: fonts,
      );
    });

    test('adding builds a PDF with one page per picture', () {
      expect(scan.pages, 3);
      expect(File(scan.pdf).existsSync(), isTrue);
      expect(pageCount(File(scan.pdf).readAsBytesSync()), 3);
    });

    test('pages can be reordered and deleted; text and PDF follow', () async {
      // Keep page 3 then page 1, drop page 2.
      await store.arrangePages(scan, [2, 0], fonts: fonts);
      expect(scan.pages, 2);
      expect(scan.text, 'trois\nun');
      expect(File(scan.page(0)).existsSync(), isTrue);
      expect(File(scan.page(1)).existsSync(), isTrue);
      expect(File(scan.page(2)).existsSync(), isFalse);
      expect(
        Directory(scan.dir).listSync().any((e) => e.path.endsWith('.moving')),
        isFalse,
      );
      // The first page is now the old third one (lightest picture).
      final first = img.decodeJpg(File(scan.page(0)).readAsBytesSync())!;
      final second = img.decodeJpg(File(scan.page(1)).readAsBytesSync())!;
      expect(first.getPixel(5, 5).r, greaterThan(150));
      expect(second.getPixel(5, 5).r, lessThan(50));
      expect(pageCount(File(scan.pdf).readAsBytesSync()), 2);
      // Survives a reload.
      await store.load();
      expect(store.scans.single.pages, 2);
      expect(store.scans.single.text, 'trois\nun');
      expect(store.search('trois'), hasLength(1));
    });

    test('invalid orders are refused before anything is touched', () async {
      for (final bad in [
        <int>[],
        [0, 0],
        [3],
        [-1],
      ]) {
        await expectLater(
          store.arrangePages(scan, bad, fonts: fonts),
          throwsArgumentError,
        );
      }
      expect(scan.pages, 3);
      expect(File(scan.page(2)).existsSync(), isTrue);
    });

    test('turning a page turns its text boxes and rebuilds the PDF', () async {
      await store.rotatePage(scan, 1, 1, fonts: fonts);
      final ocr = (await store.ocrOf(scan))!;
      expect((ocr[1].width, ocr[1].height), (140, 100));
      expect((ocr[0].width, ocr[0].height), (100, 140));
      expect(pageCount(File(scan.pdf).readAsBytesSync()), 3);
    });

    test('an older scan without OCR data can be made searchable', () async {
      File(scan.ocrFile).deleteSync();
      expect(await store.ocrOf(scan), isNull);
      await store.storeOcr(scan, [
        for (final t in ['a', 'b', 'c'])
          PageOcr(100, 140, [OcrLine(t, 1, 1, 9, 9)]),
      ], fonts);
      expect(scan.text, 'a\nb\nc');
      expect(await store.ocrOf(scan), isNotNull);
    });
  });
}
