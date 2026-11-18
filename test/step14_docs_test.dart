import 'dart:io';

import 'package:all_in_one/modules/docs/find_replace.dart';
import 'package:all_in_one/modules/docs/markdown.dart';
import 'package:all_in_one/modules/docs/markdown_edit.dart';
import 'package:all_in_one/modules/docs/markdown_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('find and replace', () {
    test('finds without case, with case, whole words', () {
      const t = 'Chat chat CHAT chatte achat';
      expect(findAll(t, 'chat'), hasLength(5)); // includes chatte and achat
      expect(findAll(t, 'chat', caseSensitive: true).map((m) => m.start), [
        5,
        15,
        23,
      ]);
      expect(findAll(t, 'chat', wholeWord: true).map((m) => m.start), [
        0,
        5,
        10,
      ]);
      expect(findAll(t, ''), isEmpty);
      expect(findAll(t, 'absent'), isEmpty);
    });

    test('matches do not overlap; accents count', () {
      expect(findAll('aaaa', 'aa'), [
        const TextMatch(0, 2),
        const TextMatch(2, 4),
      ]);
      expect(findAll('école Ecole', 'ecole'), [const TextMatch(6, 11)]);
      expect(findAll('café', 'CAFÉ'), [const TextMatch(0, 4)]);
    });

    test('whole word respects punctuation and digits', () {
      expect(findAll('a, b-c b2 b', 'b', wholeWord: true).map((m) => m.start), [
        3,
        10,
      ]);
    });

    test('replace one, replace all, with counts', () {
      expect(
        replaceMatch('un chat', const TextMatch(3, 7), 'chien'),
        'un chien',
      );
      final r = replaceEvery('chat Chat achat', 'chat', 'X');
      expect(r.text, 'X X aX');
      expect(r.count, 3);
      final w = replaceEvery('chat Chat achat', 'chat', 'X', wholeWord: true);
      expect(w.text, 'X X achat');
      final none = replaceEvery('abc', 'z', 'y');
      expect((none.text, none.count), ('abc', 0));
      // The replacement may contain the query without looping.
      expect(replaceEvery('a', 'a', 'aa').text, 'aa');
      expect(replaceEvery('a.b', '.', r'$1').text, r'a$1b');
    });

    test('next and previous match wrap around', () {
      final m = [
        const TextMatch(2, 3),
        const TextMatch(10, 11),
        const TextMatch(20, 21),
      ];
      expect(nextMatchIndex(m, 0), 0);
      expect(nextMatchIndex(m, 3), 1);
      expect(nextMatchIndex(m, 21), 0); // wraps
      expect(nextMatchIndex(m, 10, backwards: true), 0);
      expect(nextMatchIndex(m, 2, backwards: true), 2); // wraps
      expect(nextMatchIndex(const [], 0), -1);
    });
  });

  group('markdown tables', () {
    test('header, alignment and rows', () {
      final blocks = parseMarkdown(
        'Avant\n\n| Nom | Prix |\n|:---|---:|\n| Pain | 1,20 |\n| Lait | 0,95 |\n\nAprès',
      );
      expect(blocks, hasLength(3));
      final t = blocks[1] as TableBlock;
      expect(t.header, ['Nom', 'Prix']);
      expect(t.aligns, [CellAlign.left, CellAlign.right]);
      expect(t.rows, [
        ['Pain', '1,20'],
        ['Lait', '0,95'],
      ]);
      expect((blocks[2] as Paragraph).text, 'Après');
    });

    test('centre alignment, no outer pipes, short and long rows', () {
      final t =
          parseMarkdown('a | b | c\n:-:|--|--\n1 | 2\n1 | 2 | 3 | 4').single
              as TableBlock;
      expect(t.aligns.first, CellAlign.center);
      expect(t.rows, [
        ['1', '2', ''],
        ['1', '2', '3'],
      ]);
    });

    test('escaped bars stay in the cell; a lone pipe line is not a table', () {
      final t =
          parseMarkdown('| a | b |\n|---|---|\n| x \\| y | z |').single
              as TableBlock;
      expect(t.rows.single, ['x | y', 'z']);
      // No separator line: plain text.
      expect(parseMarkdown('| a | b |\n| c | d |').single, isA<Paragraph>());
      // A separator with the wrong number of columns is not a table either.
      expect(parseMarkdown('| a | b |\n|---|\ntext').first, isA<Paragraph>());
    });

    test('tables inside code fences are left alone', () {
      final b = parseMarkdown('```\n| a | b |\n|---|---|\n```');
      expect(b.single, isA<CodeBlock>());
    });
  });

  group('markdown images', () {
    test('an image on its own line is a block, with its description', () {
      final b = parseMarkdown('Texte\n\n![Mon chat](images/chat.jpg)\n\nFin');
      expect(b, hasLength(3));
      final img = b[1] as ImageBlock;
      expect((img.alt, img.src), ('Mon chat', 'images/chat.jpg'));
    });

    test('files are found relative to the document, never from the web', () {
      final dir = Directory.systemTemp.createTempSync('md_img');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/images/a b.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      expect(resolveImage('images/a%20b.png', dir.path), isNotNull);
      expect(resolveImage('images/a b.png', dir.path), isNotNull);
      expect(resolveImage('${dir.path}/images/a b.png', null), isNotNull);
      expect(resolveImage('images/absent.png', dir.path), isNull);
      expect(resolveImage('images/a b.png', null), isNull);
      expect(resolveImage('https://exemple.fr/x.png', dir.path), isNull);
      expect(resolveImage('content://media/1', dir.path), isNull);
    });
  });

  group('insert helpers', () {
    test('table goes on its own lines with its first header selected', () {
      final v = insertTable(
        const TextEditingValue(
          text: 'Avant',
          selection: TextSelection.collapsed(offset: 5),
        ),
        columns: 2,
        rows: 1,
      );
      expect(
        v.text,
        'Avant\n\n| Colonne 1 | Colonne 2 |\n| --- | --- |\n|     |     |\n',
      );
      expect(v.selection.textInside(v.text), 'Colonne 1');
      // And it parses back as a table of the requested size.
      final t = parseMarkdown(v.text).whereType<TableBlock>().single;
      expect(t.header, hasLength(2));
      expect(t.rows, hasLength(1));
    });

    test('image goes on its own line, special characters made safe', () {
      final v = insertImage(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 1),
        ),
        'Vue [du] lac',
        'images/mon lac (1).jpg',
      );
      expect(v.text, 'a\n![Vue  du  lac](images/mon%20lac%20(1%29.jpg)\nb');
      final block = parseMarkdown(v.text).whereType<ImageBlock>().single;
      expect(block.alt, 'Vue  du  lac');
    });
  });

  testWidgets('preview shows a table and a missing image placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            '| Nom | Prix |\n|---|---|\n| Pain | 1 |\n\n![Photo](nulle.png)',
            baseDir: Directory.systemTemp.path,
          ),
        ),
      ),
    );
    expect(find.text('Nom'), findsOneWidget);
    expect(find.text('Pain'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('Photo (introuvable)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
