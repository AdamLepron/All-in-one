import 'dart:async';
import 'dart:io';

import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/gallery/media_grid.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/timeline_view.dart';
import 'package:all_in_one/modules/video_editor/video_editor_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'step10_editor_test.dart' show loadFonts;

Media video(int id, {int seconds = 20}) => Media(
  id: id,
  video: true,
  path: '/v/$id.mp4',
  name: 'VID_$id.mp4',
  date: DateTime(2030, 1, 1),
  uri: 'content://media/v$id',
  width: 1920,
  height: 1080,
  duration: Duration(seconds: seconds),
);

Media photo(int id) => Media(
  id: id,
  video: false,
  path: '/p/$id.jpg',
  name: 'IMG_$id.jpg',
  date: DateTime(2030, 1, 1),
  uri: 'content://media/p$id',
  width: 4000,
  height: 3000,
);

void main() {
  late MediaLibrary library;
  late Directory tmp;
  final orientations = <Object?>[];

  Future<void> open(
    WidgetTester tester, {
    VideoExporterFn? exporter,
    Size logical = const Size(892, 412),
  }) async {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadFonts);
    orientations.clear();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    library = MediaLibrary()
      ..debugSet([video(1), video(2, seconds: 10), photo(5), photo(6)]);
    tmp = Directory.systemTemp.createTempSync('editor23');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: library,
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF5B5BD6), Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoEditorPage(
                        media: library.byKey('v1')!,
                        exporter:
                            exporter ?? (a, _) async => a['output']! as String,
                        outputDir: tmp.path,
                        opener: (_) async => null,
                        previewSounds: false,
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
    await tester.pumpAndSettle();
  }

  /// Brings a tool of the rail into view, scrolling whichever way it takes.
  Future<void> reveal(WidgetTester tester, String label) async {
    final finder = find.byKey(ValueKey('tool-$label'));
    final rail = find.descendant(
      of: find.byKey(const ValueKey('tool-rail')),
      matching: find.byType(Scrollable),
    );
    final area = tester.getRect(find.byKey(const ValueKey('tool-rail')));
    bool visible() =>
        finder.evaluate().isNotEmpty && area.contains(tester.getCenter(finder));
    for (final step in [60.0, -60.0]) {
      var guard = 0;
      while (!visible() && guard++ < 12) {
        await tester.drag(rail, Offset(0, -step));
        await tester.pumpAndSettle();
      }
      if (visible()) return;
    }
  }

  Future<void> tool(WidgetTester tester, String label) async {
    await reveal(tester, label);
    await tester.tap(find.byKey(ValueKey('tool-$label')));
    await tester.pumpAndSettle();
  }

  /// Taps something inside the side panel, scrolling it into view first.
  Future<void> press(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// Taps the visible part of a (possibly very wide) bar of the timeline.
  Future<void> tapBar(WidgetTester tester, Finder bar) async {
    final area = tester.getRect(find.byType(EditorTimeline));
    final r = tester.getRect(bar).intersect(area);
    await tester.tapAt(r.center);
    await tester.pumpAndSettle();
  }

  int nowMs(WidgetTester tester) =>
      tester.widget<EditorTimeline>(find.byType(EditorTimeline)).time.value;

  /// Moves the playhead by dragging the tracks, as a finger would.
  Future<void> scrubTo(WidgetTester tester, int ms) async {
    // A finger travels at most the width of the screen at a time, and the
    // first few pixels only wake the gesture up: so it is a closed loop.
    for (var i = 0; i < 20; i++) {
      final diff = ms - nowMs(tester);
      if (diff.abs() <= 120) return;
      final px = -(diff * defaultPxPerMs) + (diff > 0 ? -20 : 20);
      // From the empty left part, away from the handles at the playhead.
      final area = tester.getRect(find.byType(EditorTimeline));
      await tester.dragFrom(
        Offset(area.left + 150, area.center.dy),
        Offset(px.clamp(-300.0, 300.0), 0),
      );
      await tester.pumpAndSettle();
    }
  }

  String timeLabel(WidgetTester tester) => tester
      .widgetList<Text>(find.textContaining(' / '))
      .map((t) => t.data!)
      .first;

  testWidgets('opens in landscape with the tools, preview and timeline', (
    tester,
  ) async {
    await open(tester);
    expect(
      orientations.last,
      containsAll([
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]),
    );
    for (final label in [
      'Média',
      'Diviser',
      'Audio',
      'Texte',
      'Autocollant',
      'Incrustation',
      'Filtres',
      'Effets',
      'Format',
    ]) {
      await reveal(tester, label);
      expect(
        find.byKey(ValueKey('tool-$label')),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.byKey(const ValueKey('clip-0')), findsOneWidget);
    expect(find.byType(EditorTimeline), findsOneWidget);
    expect(timeLabel(tester), '0:00,0 / 0:20,0');
    expect(find.text('Exporter'), findsOneWidget);
    expect(find.text('Aperçu indisponible'), findsOneWidget);

    // Leaving gives the orientation back.
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(orientations.last, isEmpty);
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets('dragging the timeline moves the playhead; zoom changes scale', (
    tester,
  ) async {
    await open(tester);
    await scrubTo(tester, 5000);
    final at = nowMs(tester);
    expect(at, closeTo(5000, 400));
    await tester.tap(find.byTooltip('Zoom avant'));
    await tester.pumpAndSettle();
    // The same moment is still under the playhead after zooming.
    expect(nowMs(tester), closeTo(at, 60));
    await tester.tap(find.byTooltip('Zoom arrière'));
    await tester.pumpAndSettle();
    expect(nowMs(tester), closeTo(at, 60));
    await tester.tap(find.byTooltip('Début'));
    await tester.pumpAndSettle();
    expect(timeLabel(tester), startsWith('0:00'));
    await tester.tap(find.byTooltip('Fin'));
    await tester.pumpAndSettle();
    expect(timeLabel(tester), startsWith('0:20'));
  });

  testWidgets('split, delete a segment, undo and redo', (tester) async {
    await open(tester);
    // Cut at 5 s and at 10 s, then remove the middle piece.
    await scrubTo(tester, 5000);
    await tool(tester, 'Diviser');
    expect(find.byKey(const ValueKey('clip-1')), findsOneWidget);
    await scrubTo(tester, 10000);
    await tool(tester, 'Diviser');
    expect(find.byKey(const ValueKey('clip-2')), findsOneWidget);

    await tapBar(tester, find.byKey(const ValueKey('clip-1')));
    expect(find.byKey(const ValueKey('tool-Supprimer')), findsOneWidget);
    await tool(tester, 'Supprimer');
    expect(find.byKey(const ValueKey('clip-2')), findsNothing);
    // 20 s minus the 5 s piece: the rest closes up.
    expect(timeLabel(tester), endsWith('/ 0:15,0'));

    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    expect(timeLabel(tester), endsWith('/ 0:20,0'));
    expect(find.byKey(const ValueKey('clip-2')), findsOneWidget);
    await tester.tap(find.byTooltip('Rétablir'));
    await tester.pumpAndSettle();
    expect(timeLabel(tester), endsWith('/ 0:15,0'));
  });

  testWidgets('speed, volume and the other clip tools', (tester) async {
    await open(tester);
    await tapBar(tester, find.byKey(const ValueKey('clip-0')));
    await tool(tester, 'Vitesse');
    expect(find.text('Vitesse personnalisée'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screenshots/60_editor_speed.png'),
      );
    }
    await press(tester, find.text('2×'));
    expect(timeLabel(tester), endsWith('/ 0:10,0'));
    await press(tester, find.text('0,5×'));
    expect(timeLabel(tester), endsWith('/ 0:40,0'));

    await tool(tester, 'Volume');
    expect(find.text('Volume de cet extrait'), findsOneWidget);
    await tool(tester, 'Filtres');
    await press(tester, find.bySemanticsLabel('Filtre Sépia'));
    await tool(tester, 'Ajuster');
    expect(find.text('Luminosité'), findsOneWidget);
    await tool(tester, 'Effets');
    await press(tester, find.text('Zoom avant'));
    await tool(tester, 'Pivoter');
    await tool(tester, 'Miroir');
    await tool(tester, 'Dupliquer');
    expect(find.byKey(const ValueKey('clip-1')), findsOneWidget);
    // Move the copy before the original.
    await tool(tester, 'Reculer');
    expect(find.byKey(const ValueKey('clip-1')), findsOneWidget);
  });

  testWidgets('a segment is removed from the middle of a clip', (tester) async {
    await open(tester);
    await tapBar(tester, find.byKey(const ValueKey('clip-0')));
    await tool(tester, 'Segment');
    await press(tester, find.text('Retirer'));
    expect(find.text('Segment retiré'), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-1')), findsOneWidget);
    expect(timeLabel(tester), contains('/ 0:13,'));
  });

  testWidgets('trimming with the handles of the selected clip', (tester) async {
    await open(tester);
    await tapBar(tester, find.byKey(const ValueKey('clip-0')));
    // The end of the clip comes under the playhead; 80 px at 80 px per
    // second is one second off it.
    await scrubTo(tester, 20000);
    await tester.drag(
      find.byKey(const ValueKey('trim-end-0')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    expect(timeLabel(tester), contains('/ 0:19,'));
  });

  testWidgets('text and stickers are added on their own track', (tester) async {
    await open(tester);
    await tool(tester, 'Texte');
    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bar-text-0')), findsOneWidget);
    expect(find.text('Style du texte'), findsOneWidget);
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screenshots/61_editor_text.png'),
      );
    }
    expect(find.text('Bonjour'), findsWidgets); // on the bar and in the preview
    await press(tester, find.text('Rebond'));

    await tester.tap(find.byTooltip('Fermer le panneau'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 330)); // empty background: deselect
    await tester.pumpAndSettle();
    await tool(tester, 'Autocollant');
    await tester.tap(find.bySemanticsLabel('Autocollant 🔥'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bar-text-1')), findsOneWidget);

    // Splitting the selected text makes two.
    await scrubTo(tester, 1500);
    await tool(tester, 'Diviser');
    expect(find.byKey(const ValueKey('bar-text-2')), findsOneWidget);
    await tool(tester, 'Supprimer');
    expect(find.byKey(const ValueKey('bar-text-2')), findsNothing);
  });

  testWidgets('an overlay picture and a transition between two clips', (
    tester,
  ) async {
    await open(tester);
    await tool(tester, 'Incrustation');
    await tester.tap(find.text('Une photo'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(MediaThumb),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bar-overlay-0')), findsOneWidget);
    expect(find.text('Incrustation'), findsWidgets);
    expect(find.text('Taille'), findsOneWidget);
    await press(tester, find.text('Centre'));
    await tool(tester, 'Supprimer');
    expect(find.byKey(const ValueKey('bar-overlay-0')), findsNothing);

    // A second clip, then the button between the two.
    await tester.tap(find.byKey(const ValueKey('add-clip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Une vidéo'));
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
    expect(timeLabel(tester), endsWith('/ 0:30,0'));
    await tester.tap(find.byKey(const ValueKey('join-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Entre l'extrait 1"), findsOneWidget);
    await tester.ensureVisible(find.text('Glissé ←'));
    await tester.pump();
    await tester.tap(find.text('Glissé ←'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await press(tester, find.text('1 s'));
  });

  testWidgets('a photo can be a clip; the format changes the frame', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('add-clip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Une photo'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(MediaThumb),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(timeLabel(tester), endsWith('/ 0:24,0')); // 4 s photo
    // Speed does not apply to a picture.
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('tool-Vitesse'))).onTap,
      isNull,
    );
    await tool(tester, 'Format');
    expect(find.text('Format'), findsWidgets);
  });

  testWidgets('format panel and export with the right arguments', (
    tester,
  ) async {
    Map<String, Object?>? sent;
    final gate = Completer<void>();
    late void Function(int) progress;
    await open(
      tester,
      exporter: (args, onProgress) async {
        sent = args;
        progress = onProgress;
        await gate.future;
        return args['output']! as String;
      },
    );
    await tool(tester, 'Format');
    await press(tester, find.text('9:16'));
    expect(find.text('Vidéo finale : 1080 × 1920'), findsOneWidget);

    await tester.tap(find.text('Exporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Création de la vidéo'), findsOneWidget);
    progress(40);
    await tester.pump();
    expect(find.text('40 %'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget); // back on the first screen
    expect(find.textContaining('Vidéo enregistrée'), findsOneWidget);
    final args = sent!;
    expect((args['width'], args['height']), (1080, 1920));
    expect((args['output']! as String).startsWith('${tmp.path}/VID_'), true);
    expect((args['clips']! as List), hasLength(1));
  });

  testWidgets('an export failure keeps the editor open', (tester) async {
    await open(
      tester,
      exporter: (args, onProgress) async {
        throw PlatformException(code: 'export', message: 'codec indisponible');
      },
    );
    await tester.tap(find.text('Exporter'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("L'export a échoué : codec indisponible"),
      findsOneWidget,
    );
    expect(find.text('Création de la vidéo'), findsNothing);
    expect(find.byType(EditorTimeline), findsOneWidget);
  });

  testWidgets('play and pause do not break the preview', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Lecture'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lecture'), findsOneWidget);
  });

  testWidgets('a phone in portrait size still lays out without overflow', (
    tester,
  ) async {
    await open(tester, logical: const Size(412, 892));
    expect(find.byType(EditorTimeline), findsOneWidget);
  });
}
