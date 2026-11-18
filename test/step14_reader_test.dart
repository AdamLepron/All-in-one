import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/reader/annotations.dart';
import 'package:all_in_one/modules/reader/pdf_view_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('step14_reader'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('annotations', () {
    test('JSON round trip for each kind', () {
      final list = [
        Annotation(
          kind: AnnotationKind.highlight,
          page: 2,
          color: 0xFFFFD60A,
          rects: [const Rect.fromLTRB(0.1, 0.2, 0.5, 0.25)],
        ),
        Annotation(
          kind: AnnotationKind.ink,
          page: 0,
          color: 0xFF0A84FF,
          points: [const Offset(0.1, 0.1), const Offset(0.2, 0.3)],
        ),
        Annotation(
          kind: AnnotationKind.note,
          page: 1,
          color: 0xFFFF6482,
          points: [const Offset(0.5, 0.5)],
          text: 'À vérifier',
        ),
      ];
      final back = [for (final a in list) Annotation.fromJson(a.toJson())];
      expect(back[0].kind, AnnotationKind.highlight);
      expect(back[0].rects.single, const Rect.fromLTRB(0.1, 0.2, 0.5, 0.25));
      expect(back[1].points, hasLength(2));
      expect((back[2].text, back[2].page), ('À vérifier', 1));
    });

    test('hit testing: highlight, ink segment, note', () {
      final h = Annotation(
        kind: AnnotationKind.highlight,
        page: 0,
        color: 0,
        rects: [const Rect.fromLTRB(0.2, 0.2, 0.6, 0.3)],
      );
      expect(h.hits(const Offset(0.4, 0.25), 0.01), isTrue);
      expect(h.hits(const Offset(0.4, 0.5), 0.01), isFalse);
      final ink = Annotation(
        kind: AnnotationKind.ink,
        page: 0,
        color: 0,
        points: [const Offset(0.1, 0.1), const Offset(0.5, 0.1)],
      );
      // Between the two points of the stroke, not only near them.
      expect(ink.hits(const Offset(0.3, 0.105), 0.01), isTrue);
      expect(ink.hits(const Offset(0.3, 0.2), 0.01), isFalse);
      final note = Annotation(
        kind: AnnotationKind.note,
        page: 0,
        color: 0,
        points: [const Offset(0.5, 0.5)],
        text: 'x',
      );
      expect(note.hits(const Offset(0.51, 0.5), 0.01), isTrue);
      expect(note.hits(const Offset(0.7, 0.5), 0.01), isFalse);
    });

    test(
      'store: one file per PDF, empty list removes it, damage is ignored',
      () async {
        final store = AnnotationStore(directory: () async => '${tmp.path}/a');
        expect(await store.load('/x/a.pdf'), isEmpty);
        final note = Annotation(
          kind: AnnotationKind.note,
          page: 0,
          color: 1,
          points: [const Offset(0.1, 0.1)],
          text: 't',
        );
        await store.save('/x/a.pdf', [note]);
        await store.save('/x/b.pdf', [note, note]);
        expect(await store.load('/x/a.pdf'), hasLength(1));
        expect(await store.load('/x/b.pdf'), hasLength(2));
        expect(Directory('${tmp.path}/a').listSync(), hasLength(2));
        await store.save('/x/a.pdf', []);
        expect(Directory('${tmp.path}/a').listSync(), hasLength(1));
        // A damaged file reads as no annotations.
        final file = Directory('${tmp.path}/a').listSync().single as File;
        file.writeAsStringSync('{oops');
        expect(await store.load('/x/b.pdf'), isEmpty);
      },
    );
  });

  test(
    'saves made one after the other end in the order they were made',
    () async {
      final store = AnnotationStore(directory: () async => '${tmp.path}/q');
      final note = Annotation(
        kind: AnnotationKind.note,
        page: 0,
        color: 1,
        points: [const Offset(0.1, 0.1)],
        text: 't',
      );
      // Add then undo, without waiting in between.
      final first = store.save('/x/a.pdf', [note]);
      final second = store.save('/x/a.pdf', []);
      await Future.wait([first, second]);
      expect(await store.load('/x/a.pdf'), isEmpty);
      expect(Directory('${tmp.path}/q').listSync(), isEmpty);
      // And the other way round.
      final a = store.save('/x/a.pdf', []);
      final b = store.save('/x/a.pdf', [note]);
      await Future.wait([a, b]);
      expect(await store.load('/x/a.pdf'), hasLength(1));
    },
  );

  testWidgets('PDF viewer: search, results, outline and a note', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('allinone/media'), (
          call,
        ) async {
          calls.add(call.method);
          switch (call.method) {
            case 'pdfOpen':
              return {
                'id': 1,
                'count': 3,
                'sizes': [600.0, 800.0, 600.0, 800.0, 600.0, 800.0],
              };
            case 'pdfOutline':
              return [
                {'title': 'Introduction', 'page': 0, 'level': 0},
                {'title': 'Détails', 'page': 2, 'level': 1},
              ];
            case 'pdfSearch':
              return [
                {
                  'page': 0,
                  'snippet': 'un mot clé ici',
                  'rects': [
                    [0.1, 0.1, 0.3, 0.12],
                  ],
                },
                {
                  'page': 2,
                  'snippet': 'encore le mot clé',
                  'rects': [
                    [0.2, 0.5, 0.4, 0.52],
                  ],
                },
              ];
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('allinone/media'),
            null,
          ),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = AnnotationStore(directory: () async => '${tmp.path}/ann');
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: PdfViewPage(path: '${tmp.path}/doc.pdf', annotations: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    // Search.
    await tester.tap(find.byTooltip('Rechercher'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'mot clé');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(calls, contains('pdfSearch'));
    expect(find.textContaining('1 / 2 · page 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Résultat suivant'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 / 2 · page 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Résultat suivant')); // wraps around
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2 · page 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Liste des résultats'));
    await tester.pumpAndSettle();
    expect(find.text('encore le mot clé'), findsOneWidget);
    await tester.tap(find.text('encore le mot clé'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Fermer la recherche'));
    await tester.pumpAndSettle();

    // Table of contents.
    await tester.tap(find.byTooltip('Sommaire'));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
    await tester.tap(find.text('Détails'));
    await tester.pumpAndSettle();

    // A note on a page.
    await tester.tap(find.byTooltip('Annoter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 300));
    // The viewer also listens for a double tap, so a single one is confirmed
    // only after that delay.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle note'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Ma remarque');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    // The note is kept on disk, next to the app's data.
    Future<List<Annotation>?> onDisk({required bool expectSome}) async {
      final reader = AnnotationStore(directory: () async => '${tmp.path}/ann');
      List<Annotation>? list;
      // The viewer writes in the background, one awaited step at a time:
      // alternate real I/O time with pumping the fake clock.
      for (var i = 0; i < 40; i++) {
        list = await tester.runAsync(() => reader.load('${tmp.path}/doc.pdf'));
        if (list!.isNotEmpty == expectSome) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      return list;
    }

    final saved = await onDisk(expectSome: true);
    expect(saved, hasLength(1));
    expect(saved!.single.text, 'Ma remarque');
    expect(find.byTooltip('Annuler la dernière annotation'), findsOneWidget);
    await tester.tap(find.byTooltip('Annuler la dernière annotation'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed,
      isNull,
      reason: 'the note is gone from the screen',
    );
    // (Removal from the disk is covered by the store test above.)
  });
}
