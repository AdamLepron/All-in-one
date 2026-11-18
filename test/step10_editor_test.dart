import 'dart:async';
import 'dart:io';

import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/gallery/media_grid.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/video_editor_home.dart';
import 'package:all_in_one/modules/video_editor/video_editor_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

Media video(int id, int seconds) => Media(
  id: id,
  video: true,
  path: '/v/$id.mp4',
  name: 'VID_$id.mp4',
  date: DateTime(2026, 11, 17, 10, id),
  uri: 'content://media/external/video/media/$id',
  width: 1920,
  height: 1080,
  duration: Duration(seconds: seconds),
);

void main() {
  late MediaLibrary library;

  Future<void> start(
    WidgetTester tester,
    VideoExporterFn exporter,
    String dir,
  ) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadFonts);
    library = MediaLibrary()
      ..debugSet([video(1, 60), video(2, 20), video(3, 8)]);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: library,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoEditorPage(
                        media: library.byKey('v1')!,
                        exporter: exporter,
                        outputDir: dir,
                      ),
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
    await tester.pump();
    // The player never answers in tests: after its timeout the preview
    // gives up and the screen settles.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('home lists the videos of the library', (tester) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MediaLibrary()..debugSet([video(1, 60), video(2, 20)]),
        child: const MaterialApp(home: VideoEditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Choisissez la première vidéo'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('a montage is built and exported with the right arguments', (
    tester,
  ) async {
    Map<String, Object?>? sent;
    final gate = Completer<void>();
    late void Function(int) progress;
    final tmp = Directory.systemTemp.createTempSync('montage_test');
    addTearDown(() => tmp.deleteSync(recursive: true));

    await start(tester, (args, onProgress) async {
      sent = args;
      progress = onProgress;
      await gate.future;
      return args['output']! as String;
    }, tmp.path);

    // No player in tests: the preview says so, editing still works.
    expect(find.text('Aperçu indisponible'), findsOneWidget);
    expect(find.text('Durée finale 1:00,0 · 1 extrait'), findsOneWidget);
    await shot(tester, '56_video_editor');

    // Trim to 10 s – 40 s.
    tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
      const RangeValues(10000, 40000),
    );
    await tester.pump();
    expect(find.text('Durée finale 0:30,0 · 1 extrait'), findsOneWidget);
    expect(find.text('Début 0:10,0'), findsOneWidget);

    // Double speed halves it.
    await tester.tap(find.text('Vitesse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2×'));
    await tester.pumpAndSettle();
    expect(find.text('Durée finale 0:15,0 · 1 extrait'), findsOneWidget);
    expect(find.textContaining('dure 0:15,0'), findsOneWidget);
    await shot(tester, '57_video_speed');

    await tester.tap(find.byTooltip('Pivoter à droite'));
    await tester.pump();

    // A second video joins the montage and becomes the selected clip.
    await tester.tap(find.byTooltip('Ajouter une vidéo'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(MediaThumb),
          )
          .at(1),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2 extraits'), findsOneWidget);

    // Duplicating and deleting keep the count right.
    await tester.tap(find.byTooltip('Dupliquer'));
    await tester.pump();
    expect(find.textContaining('3 extraits'), findsOneWidget);
    await tester.tap(find.byTooltip("Supprimer l'extrait"));
    await tester.pump();
    expect(find.textContaining('2 extraits'), findsOneWidget);

    // Audio: muting the original sound.
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await shot(tester, '58_video_audio');

    // Export shows progress and finishes by closing the editor.
    await tester.tap(find.text('Exporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Création de la vidéo'), findsOneWidget);
    expect(find.text('Préparation…'), findsOneWidget);
    progress(40);
    await tester.pump();
    expect(find.text('40 %'), findsOneWidget);
    await shot(tester, '59_video_export');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget); // back on the first screen
    expect(find.textContaining('Vidéo enregistrée'), findsOneWidget);

    final args = sent!;
    expect((args['output']! as String).startsWith('${tmp.path}/VID_'), true);
    expect((args['output']! as String).endsWith('.mp4'), true);
    expect(args['muteOriginal'], true);
    expect(args['music'], isNull);
    expect((args['width'], args['height']), (1080, 1920)); // first clip rotated
    final clips = args['clips']! as List;
    expect(clips.length, 2);
    expect(clips.first, {
      'uri': 'content://media/external/video/media/1',
      'startMs': 10000,
      'endMs': 40000,
      'speed': 2.0,
      'rotation': 90,
      'volume': 1.0,
      'fadeInMs': 0,
      'fadeOutMs': 0,
      'flip': false,
      'effect': 0,
      'blur': 0.0,
    });
    expect(
      (clips.last as Map)['uri'],
      'content://media/external/video/media/2',
    );
    expect((clips.last as Map)['speed'], 1.0);
  });

  testWidgets('failure and leaving are handled', (tester) async {
    await start(tester, (args, onProgress) async {
      throw PlatformException(code: 'export', message: 'codec indisponible');
    }, Directory.systemTemp.path);

    // Nothing edited yet: closing leaves at once.
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);

    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vitesse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0,5×'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exporter'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("L'export a échoué : codec indisponible"),
      findsOneWidget,
    );
    expect(find.text('Création de la vidéo'), findsNothing); // dialog closed
    expect(find.text('Montage'), findsOneWidget); // still editing

    // With changes, closing asks first.
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Abandonner le montage ?'), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Montage'), findsOneWidget);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandonner'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);
  });
}
