import 'dart:io';

import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/video_editor_page.dart';
import 'package:all_in_one/modules/video_editor/video_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'step10_editor_test.dart' show loadFonts;

Media video(int id, {int w = 1920, int h = 1080}) => Media(
  id: id,
  video: true,
  path: '/v/$id.mp4',
  name: 'VID_$id.mp4',
  date: DateTime(2030, 1, 1),
  uri: 'content://media/$id',
  width: w,
  height: h,
  duration: const Duration(seconds: 20),
);

void main() {
  group('looks', () {
    test('an untouched clip has a neutral look and nothing is sent', () {
      final p = VideoProject(video(1));
      expect(p.clips.first.look.isNeutral, isTrue);
      expect(p.clips.first.styled, isFalse);
      final sent = (p.exportArgs('/o.mp4')['clips']! as List).first as Map;
      expect(sent.containsKey('colorMatrix'), isFalse);
      expect(sent['effect'], 0);
      expect(sent['flip'], false);
    });

    test('black and white gives equal red, green and blue', () {
      final c = Clip(video(1))..filter = VideoFilter.mono;
      final m = c.look.matrix;
      for (var i = 0; i < 3; i++) {
        expect(m[i], closeTo(m[3 + i], 1e-9));
        expect(m[i], closeTo(m[6 + i], 1e-9));
      }
      // Each row keeps white white.
      expect(m[0] + m[1] + m[2], closeTo(1, 1e-9));
    });

    test('brightness scales, contrast of a preset adds to the slider', () {
      final c = Clip(video(1))
        ..filter = VideoFilter.noir
        ..contrastAdjust = 0.2
        ..brightness = 1.2;
      expect(c.look.contrast, closeTo(0.55, 1e-9));
      expect(
        c.look.matrix[0] + c.look.matrix[1] + c.look.matrix[2],
        closeTo(1.2, 1e-9),
      );
    });

    test('the native matrix is 4x4 column-major, alpha untouched', () {
      final c = Clip(video(1))..filter = VideoFilter.warm;
      final m = c.look.columnMajor4;
      expect(m, hasLength(16));
      expect(m[0], closeTo(1.12, 1e-9)); // red gain
      expect(m[10], closeTo(0.86, 1e-9)); // blue gain
      expect(m[15], 1);
      expect([m[3], m[7], m[11], m[12], m[13], m[14]], everyElement(0));
    });

    test('a styled clip sends its look, effect, blur and mirror', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..filter = VideoFilter.sepia
        ..effect = ClipEffect.zoomIn
        ..blur = 0.4
        ..flip = true;
      final sent = (p.exportArgs('/o.mp4')['clips']! as List).first as Map;
      expect((sent['colorMatrix'] as List), hasLength(16));
      expect(sent['effect'], ClipEffect.zoomIn.index);
      expect(sent['blur'], 0.4);
      expect(sent['flip'], true);
    });

    test('reset restores the picture; copies keep everything', () {
      final c = Clip(video(1))
        ..filter = VideoFilter.vivid
        ..brightness = 1.3
        ..saturationAdjust = 1.7
        ..effect = ClipEffect.shake;
      final copy = c.copy();
      expect(copy.filter, VideoFilter.vivid);
      expect(copy.effect, ClipEffect.shake);
      c.resetLook();
      expect(c.look.isNeutral, isTrue);
      expect(c.effect, ClipEffect.shake); // motion is not part of the look
    });

    test('everything survives saving, and old projects still load', () {
      final p = VideoProject(video(1))
        ..aspect = Aspect.tall
        ..fillFrame = true;
      p.clips.first
        ..filter = VideoFilter.cinema
        ..brightness = 0.8
        ..effect = ClipEffect.pulse
        ..blur = 0.3
        ..flip = true;
      p.titles.add(
        TitleItem(
          '🔥',
          align: 1,
          animation: TitleAnimation.pop,
          box: TitleBox.none,
        ),
      );
      final back = VideoProject.fromJson(p.toJson());
      final c = back.clips.first;
      expect(
        (c.filter, c.effect, c.blur, c.flip),
        (VideoFilter.cinema, ClipEffect.pulse, 0.3, true),
      );
      expect(c.brightness, 0.8);
      expect((back.aspect, back.fillFrame), (Aspect.tall, true));
      final t = back.titles.single;
      expect(
        (t.align, t.animation, t.box),
        (1, TitleAnimation.pop, TitleBox.none),
      );

      // A project saved by version 1.x has none of these keys.
      final old = p.toJson();
      (old['clips'] as List).first
        ..remove('filter')
        ..remove('effect')
        ..remove('blur')
        ..remove('flip')
        ..remove('brightness');
      old
        ..remove('aspect')
        ..remove('fill');
      (old['titles'] as List).first
        ..remove('align')
        ..remove('animation')
        ..remove('box');
      final legacy = VideoProject.fromJson(old);
      expect(legacy.clips.first.styled, isFalse);
      expect(legacy.aspect, Aspect.original);
      expect(legacy.titles.single.box, TitleBox.shade);
    });

    test('bad values in a saved project are tamed', () {
      final p = VideoProject(video(1));
      final j = p.toJson();
      (j['clips'] as List).first
        ..['brightness'] = 99
        ..['saturation'] = -4
        ..['filter'] = 'nope';
      final c = VideoProject.fromJson(j).clips.first;
      expect(
        (c.brightness, c.saturationAdjust, c.filter),
        (1.5, 0.0, VideoFilter.none),
      );
    });
  });

  group('frame shape', () {
    test('original keeps the first clip shape, scaled to the limit', () {
      final p = VideoProject(video(1, w: 3840, h: 2160));
      expect(p.outputSize, const Size(1920, 1080));
    });

    test('chosen shapes have even sides and the right ratio', () {
      final p = VideoProject(video(1));
      p.aspect = Aspect.tall;
      expect(p.outputSize, const Size(1080, 1920));
      p.aspect = Aspect.square;
      expect(p.outputSize, const Size(1920, 1920));
      p.aspect = Aspect.portrait;
      expect(p.outputSize, const Size(1536, 1920));
      p.aspect = Aspect.classic;
      expect(p.outputSize.width / p.outputSize.height, closeTo(4 / 3, 0.01));
      expect(p.outputSize.width % 2, 0);
      expect(p.outputSize.height % 2, 0);
    });

    test('a small source is not enlarged', () {
      final p = VideoProject(video(1, w: 1280, h: 720))..aspect = Aspect.tall;
      expect(p.outputSize.height, 1280);
    });

    test('export arguments carry the frame and fill mode', () {
      final p = VideoProject(video(1))
        ..aspect = Aspect.tall
        ..fillFrame = true;
      final a = p.exportArgs('/o.mp4');
      expect((a['width'], a['height'], a['fill']), (1080, 1920, true));
    });
  });

  group('titles', () {
    test('style is sent to the exporter', () {
      final p = VideoProject(video(1));
      p.titles.add(
        TitleItem(
          'Salut',
          align: -1,
          animation: TitleAnimation.slide,
          box: TitleBox.solid,
        ),
      );
      final t = (p.exportArgs('/o.mp4')['titles']! as List).first as Map;
      expect(
        (t['align'], t['animation'], t['box']),
        (-1, TitleAnimation.slide.index, TitleBox.solid.index),
      );
    });
  });

  group('screens', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(824, 1784);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadFonts);
      final library = MediaLibrary()..debugSet([video(1)]);
      final tmp = Directory.systemTemp.createTempSync('fx');
      addTearDown(() => tmp.deleteSync(recursive: true));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: library,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
            home: VideoEditorPage(
              media: library.byKey('v1')!,
              exporter: (a, _) async => a['output']! as String,
              outputDir: tmp.path,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
    }

    testWidgets('filters, effects and format panels change the clip', (
      tester,
    ) async {
      await open(tester);
      // Every tool is reachable in the row.
      for (final label in ['Couper', 'Vitesse', 'Audio', 'Titres']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.ensureVisible(find.text('Filtres'));
      await tester.tap(find.text('Filtres'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Filtre Sépia'));
      await tester.pumpAndSettle();
      expect(find.text('Sépia'), findsOneWidget);
      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Effets'));
      await tester.tap(find.text('Effets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zoom avant'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Format'));
      await tester.tap(find.text('Format'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9:16'));
      await tester.pumpAndSettle();
      expect(find.text('Vidéo finale : 1080 × 1920'), findsOneWidget);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('les bords sont rognés'), findsOneWidget);
    });

    testWidgets('a sticker is added as a title and can be restyled', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Titres'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Autocollant'));
      await tester.tap(find.text('Autocollant'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Autocollant 🔥'));
      await tester.pumpAndSettle();
      expect(find.text('🔥'), findsWidgets);
      await tester.ensureVisible(find.text('Droite'));
      await tester.tap(find.text('Droite'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Glissé'));
      await tester.tap(find.text('Glissé'));
      await tester.pumpAndSettle();
      expect(find.text('Plein'), findsOneWidget);
    });
  });
}
