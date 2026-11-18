import 'dart:io';

import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/photo/photo_editor_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

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

/// A 600 × 400 landscape: sky gradient, sun and green hills.
Uint8List landscape() {
  final image = img.Image(width: 600, height: 400);
  for (final p in image) {
    final t = p.y / 400;
    if (p.y > 270 + 20 * (p.x / 600 - 0.5) * (p.x / 600 - 0.5) * 8) {
      p.setRgb(40 + (p.x ~/ 12), 130 - (p.y - 270) ~/ 3, 60);
    } else {
      p.setRgb(
        (70 + 150 * t).round(),
        (130 + 60 * t).round(),
        (220 - 60 * t).round(),
      );
    }
  }
  img.fillCircle(
    image,
    x: 430,
    y: 150,
    radius: 46,
    color: img.ColorRgb8(255, 214, 90),
  );
  return img.encodeJpg(image, quality: 95);
}

void main() {
  testWidgets('editing flow ends with a saved copy and an untouched original', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late Directory tmp;
    late String source;
    await tester.runAsync(() async {
      await loadFonts();
      tmp = await Directory.systemTemp.createTemp('editor_test');
      source = '${tmp.path}/paysage.jpg';
      await File(source).writeAsBytes(landscape());
    });
    addTearDown(() => tmp.deleteSync(recursive: true));
    final originalBytes = File(source).readAsBytesSync();

    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
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

    final out = '${tmp.path}/out';
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MediaLibrary(),
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PhotoEditorPage(path: source, outputDir: out),
                    ),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await settle();

    // Nothing edited yet: nothing to save or undo.
    FilledButton saveButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enregistrer'),
    );
    expect(saveButton().onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.undo_rounded),
          )
          .onPressed,
      isNull,
    );
    await shot('45_editor');

    // Raising brightness with the slider enables saving and undoing.
    await tester.drag(find.byType(Slider), const Offset(45, 0));
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
    await tester.tap(find.text('Contraste'));
    await tester.pump();
    await tester.drag(find.byType(Slider), const Offset(40, 0));
    await tester.pump();
    await shot('46_editor_adjust');

    // Filters, then undo goes back one step at a time.
    await tester.tap(find.text('Filtres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sépia'));
    await tester.pumpAndSettle();
    expect(find.text('Intensité'), findsOneWidget);
    await shot('47_editor_filters');
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez un filtre'), findsOneWidget);
    await tester.tap(find.byTooltip('Rétablir'));
    await tester.pumpAndSettle();
    expect(find.text('Intensité'), findsOneWidget);

    // Square crop, then a quarter turn.
    await tester.tap(find.text('Rogner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();
    await shot('48_editor_crop');
    await tester.tap(find.byTooltip('Pivoter à droite'));
    await tester.pumpAndSettle();

    // A stroke across the picture.
    await tester.tap(find.text('Dessiner'));
    await tester.pumpAndSettle();
    final canvas = tester.getCenter(find.byType(CustomPaint).first);
    final gesture = await tester.startGesture(canvas - const Offset(120, 40));
    await gesture.moveBy(const Offset(80, 60));
    await gesture.moveBy(const Offset(80, -30));
    await gesture.up();
    await tester.pumpAndSettle();
    await shot('49_editor_draw');

    // Leaving with unsaved work asks first.
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    // Save: a new file appears, the original stays byte for byte the same.
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    // The options sheet first: keep the defaults (JPEG, original size).
    expect(find.text("Options d'enregistrement"), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Enregistrer'),
      ),
    );
    await settle();
    expect(find.text('Ouvrir'), findsOneWidget); // back on the first screen
    final saved = Directory(out).listSync().whereType<File>().toList();
    expect(saved.length, 1);
    final result = img.decodeJpg(saved.single.readAsBytesSync())!;
    expect(
      (result.width, result.height),
      (400, 400),
    ); // square crop of 600 × 400
    expect(File(source).readAsBytesSync(), originalBytes);
  });
}
