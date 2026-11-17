import 'dart:io';

import 'package:all_in_one/modules/docs/pdf_export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PdfFonts> fonts() async {
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

  /// Page count read from the document's page tree.
  int pages(List<int> bytes) => int.parse(
    RegExp(r'/Count (\d+)').firstMatch(String.fromCharCodes(bytes))!.group(1)!,
  );

  testWidgets('fonts load from the bundled assets', (tester) async {
    await tester.runAsync(() async {
      await PdfFonts.load(); // would throw if the assets were not declared
    });
  });

  testWidgets('markdown becomes a valid PDF, with as many pages as needed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = await fonts();
      const source = '''
# Compte rendu — œuvre à 5 €

Un paragraphe avec **gras**, *italique*, ~~barré~~, `code` et [un lien](https://exemple.fr).

- puce « typographique »
  - sous-puce
1. un
2. deux
- [ ] à faire
- [x] fait

> Une citation

---

```
bloc de code
```
''';
      final one = await markdownToPdf(source, title: 'Compte rendu', fonts: f);
      expect(String.fromCharCodes(one.take(5)), '%PDF-');
      expect(one.length, greaterThan(3000));
      expect(pages(one), 1);

      // A long document flows over several pages.
      final long = List.generate(
        200,
        (i) =>
            'Ligne numéro $i : un texte assez long pour remplir de la place.',
      ).join('\n\n');
      final many = await markdownToPdf(long, title: 'Long', fonts: f);
      expect(pages(many), greaterThan(3));

      // An empty document still gives a valid file.
      final empty = await markdownToPdf('', title: 'Vide', fonts: f);
      expect(String.fromCharCodes(empty.take(5)), '%PDF-');
      expect(pages(empty), 1);
    });
  });
}
