import 'dart:io';

import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/docs/docs_page.dart';
import 'package:all_in_one/modules/docs/pdf_export.dart';
import 'package:all_in_one/modules/transfer/transfer_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  if (!Directory(dir).existsSync()) return;
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(read('Roboto-$f.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

void main() {
  testWidgets('writing a document: lists, autosave, preview, PDF, library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late Directory tmp;
    late PdfFonts fonts;
    await tester.runAsync(() async {
      await loadFonts();
      tmp = await Directory.systemTemp.createTemp('docs_ui');
      Future<pw.Font> f(String n) async => pw.Font.ttf(
        ByteData.sublistView(await File('assets/fonts/$n.ttf').readAsBytes()),
      );
      fonts = PdfFonts(
        await f('Roboto-Regular'),
        await f('Roboto-Bold'),
        await f('Roboto-Italic'),
        await f('Roboto-BoldItalic'),
      );
    });
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dir = '${tmp.path}/docs';

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> shot(String name) async {
      if (!autoUpdateGoldenFiles) return;
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screenshots/$name.png'),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
        home: DocsPage(directory: dir),
      ),
    );
    await settle();
    expect(find.text('Aucun document'), findsOneWidget);
    await shot('50_docs_empty');

    // New document: the title becomes the file name after the first save.
    await tester.tap(find.text('Nouveau document'));
    await settle();
    final field = find.byType(TextField);
    await tester.enterText(
      field,
      '# Courses du week-end\n\nPenser à **tout** vérifier.\n\n- lait',
    );
    await tester.pump();
    // Enter after a list item starts the next one.
    await tester.enterText(
      field,
      '# Courses du week-end\n\nPenser à **tout** vérifier.\n\n- lait\n',
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.text.endsWith('- lait\n- '),
      true,
    );
    await tester.enterText(
      field,
      '# Courses du week-end\n\nPenser à **tout** vérifier.\n\n- lait\n- pain\n- [ ] œufs\n- [x] café\n\n> Ne pas oublier les sacs.',
    );
    await tester.pump();
    expect(find.textContaining('mots'), findsOneWidget);
    await shot('51_editor');

    // The toolbar edits the selection.
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 9);
    await tester.tap(find.byTooltip('Italique'));
    await tester.pump();
    expect(controller.text.startsWith('# *Courses* du'), true);
    // The undo history records a change after a short pause.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pump();
    expect(controller.text.startsWith('# Courses du'), true);
    await tester.tap(find.byTooltip('Rétablir'));
    await tester.pump();
    expect(controller.text.startsWith('# *Courses* du'), true);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pump();
    expect(controller.text.startsWith('# Courses du'), true);

    // Autosave creates the file, named after the first line.
    await tester.pump(const Duration(seconds: 2));
    final file = File('$dir/Courses du week-end.md');
    expect(file.existsSync(), true);
    expect(file.readAsStringSync(), contains('- [ ] œufs'));
    expect(find.text('Enregistré'), findsOneWidget);

    // Preview shows formatted text, not markers.
    await tester.tap(find.byTooltip('Aperçu'));
    await tester.pumpAndSettle();
    expect(find.text('Courses du week-end'), findsWidgets);
    expect(find.textContaining('# '), findsNothing);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    await shot('52_preview');
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();

    // PDF export next to the document.
    await tester.pageBack();
    await settle();
    expect(find.text('Courses du week-end'), findsOneWidget);
    await tester.tap(find.text('Courses du week-end'));
    await settle();
    await tester.tap(find.byTooltip('Exporter en PDF'));
    await settle();
    expect(File('$dir/Courses du week-end.pdf').existsSync(), true);
    expect(File('$dir/Courses du week-end.pdf').readAsBytesSync().take(4), [
      0x25,
      0x50,
      0x44,
      0x46,
    ]);

    // Back in the library the document shows, with a readable preview.
    await tester.pageBack();
    await settle();
    expect(find.text('Courses du week-end'), findsOneWidget);
    await shot('53_docs_library');
    expect(fonts.regular, isNotNull);
  }, skip: false);

  testWidgets('transfer screens', (tester) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    late Directory tmp;
    await tester.runAsync(() async {
      await loadFonts();
      tmp = await Directory.systemTemp.createTemp('transfer_ui');
    });
    addTearDown(() => tmp.deleteSync(recursive: true));

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> shot(String name) async {
      if (!autoUpdateGoldenFiles) return;
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screenshots/$name.png'),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
        home: TransferPage(receiveDirectory: '${tmp.path}/recus'),
      ),
    );
    expect(find.text('Envoyer des fichiers'), findsOneWidget);
    expect(find.textContaining('sur le même réseau Wi-Fi'), findsOneWidget);
    await shot('54_transfer');

    await tester.tap(find.text('Recevoir des fichiers'));
    await settle();
    expect(find.text('Arrêter le partage'), findsOneWidget);
    await shot('55_transfer_receive');
    // Leaving stops the server and returns to the menu.
    await tester.tap(find.text('Arrêter le partage'));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer des fichiers'), findsOneWidget);
  });
}
