import 'package:all_in_one/modules/docs/docs_store.dart';
import 'package:all_in_one/modules/docs/markdown.dart';
import 'package:all_in_one/modules/docs/markdown_edit.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue value(String text, [int? start, int? end]) => TextEditingValue(
  text: text,
  selection: TextSelection(
    baseOffset: start ?? text.length,
    extentOffset: end ?? start ?? text.length,
  ),
);

void main() {
  group('markdown blocks', () {
    test('every kind of block', () {
      final blocks = parseMarkdown(
        '# Titre\n\nUn paragraphe\nsur deux lignes.\n\n- un\n- deux\n  - sous-élément\n\n'
        '1. premier\n2. second\n\n- [ ] à faire\n- [x] fait\n\n> citation\n> suite\n\n---\n\n```\ncode\n  indenté\n```\n',
      );
      expect(blocks[0], isA<Heading>().having((h) => h.level, 'level', 1));
      expect((blocks[1] as Paragraph).text, 'Un paragraphe\nsur deux lignes.');
      expect((blocks[2] as ListItem).text, 'un');
      expect((blocks[4] as ListItem).indent, 1);
      expect((blocks[5] as ListItem).number, 1);
      expect((blocks[6] as ListItem).number, 2);
      expect((blocks[7] as ListItem).checked, false);
      expect((blocks[8] as ListItem).checked, true);
      expect((blocks[9] as Quote).text, 'citation\nsuite');
      expect(blocks[10], isA<Rule>());
      expect((blocks[11] as CodeBlock).code, 'code\n  indenté');
      expect(blocks.length, 12);
    });

    test('odd input never throws', () {
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('\n\n  \n'), isEmpty);
      expect(
        (parseMarkdown('```\nnon fermé')[0] as CodeBlock).code,
        'non fermé',
      );
      expect(parseMarkdown('#pas un titre').single, isA<Paragraph>());
      expect(parseMarkdown('####### trop profond').single, isA<Paragraph>());
      expect(parseMarkdown('a\r\nb').single, isA<Paragraph>());
      expect(parseMarkdown('* * *').single, isA<Rule>());
    });
  });

  group('inline styles', () {
    test('combinations and nesting', () {
      expect(parseInline('a **gras** et *italique* et `code`'), const [
        Span('a '),
        Span('gras', bold: true),
        Span(' et '),
        Span('italique', italic: true),
        Span(' et '),
        Span('code', code: true),
      ]);
      expect(parseInline('**gras et *italique***'), const [
        Span('gras et ', bold: true),
        Span('italique', bold: true, italic: true),
      ]);
      expect(parseInline('~~barré~~'), const [Span('barré', strike: true)]);
      expect(parseInline('voir [le site](https://exemple.fr)'), const [
        Span('voir '),
        Span('le site', link: 'https://exemple.fr'),
      ]);
    });

    test('markers that are not styles stay as text', () {
      expect(parseInline('snake_case_name'), const [Span('snake_case_name')]);
      expect(parseInline('2 * 3 * 4'), const [Span('2 * 3 * 4')]);
      expect(parseInline('*non fermé'), const [Span('*non fermé')]);
      expect(parseInline('`code *non* italique`'), const [
        Span('code *non* italique', code: true),
      ]);
      expect(parseInline(''), isEmpty);
    });

    test('statistics', () {
      expect(textStats('Bonjour tout  le monde\nfin'), (
        words: 5,
        characters: 26,
      ));
      expect(textStats('').words, 0);
    });
  });

  group('editing helpers', () {
    test('wrapping toggles on and off', () {
      var v = toggleWrap(value('un deux trois', 3, 7), '**');
      expect(v.text, 'un **deux** trois');
      expect(v.selection, const TextSelection(baseOffset: 5, extentOffset: 9));
      v = toggleWrap(v, '**'); // selection is the bare word inside the markers
      expect(v.text, 'un deux trois');
      expect(v.selection, const TextSelection(baseOffset: 3, extentOffset: 7));
      // Selecting the markers too also removes them.
      expect(
        toggleWrap(value('un **deux** trois', 3, 11), '**').text,
        'un deux trois',
      );
      // Nothing selected: markers inserted around the caret.
      v = toggleWrap(value('ab', 1), '*');
      expect(v.text, 'a**b');
      expect(v.selection.baseOffset, 2);
    });

    test('line prefixes', () {
      var v = toggleBullets(value('un\ndeux\ntrois', 0, 7));
      expect(v.text, '- un\n- deux\ntrois');
      v = toggleBullets(v); // all selected lines already bulleted
      expect(v.text, 'un\ndeux\ntrois');
      expect(toggleNumbers(value('a\nb\nc', 0, 5)).text, '1. a\n2. b\n3. c');
      // Switching kinds replaces the old prefix.
      expect(toggleChecklist(value('- a\n- b', 0, 7)).text, '- [ ] a\n- [ ] b');
      expect(toggleQuote(value('texte', 2)).text, '> texte');
      expect(toggleQuote(value('> texte', 4)).text, 'texte');
      // Only the line at the caret changes.
      expect(toggleBullets(value('un\ndeux', 5)).text, 'un\n- deux');
      // A selection ending right after a newline leaves the next line alone.
      expect(toggleBullets(value('un\ndeux', 0, 3)).text, '- un\ndeux');
    });

    test('heading cycle', () {
      var v = value('Titre', 2);
      v = cycleHeading(v);
      expect(v.text, '# Titre');
      v = cycleHeading(v);
      expect(v.text, '## Titre');
      v = cycleHeading(v);
      expect(v.text, '### Titre');
      v = cycleHeading(v);
      expect(v.text, 'Titre');
      expect(
        cycleHeading(value('a\n- b', 4)).text,
        'a\n# b',
      ); // replaces a list prefix
    });

    test('links and rules', () {
      expect(
        insertLink(value('voir ici', 5, 8), 'https://x.fr').text,
        'voir [ici](https://x.fr)',
      );
      expect(
        insertLink(value('', 0), 'https://x.fr').text,
        '[lien](https://x.fr)',
      );
      expect(insertRule(value('texte', 5)).text, 'texte\n\n---\n\n');
      expect(insertRule(value('', 0)).text, '\n---\n\n');
    });

    test('Enter continues lists', () {
      final f = ListContinuation();
      TextEditingValue enter(String before, [String after = '']) =>
          f.formatEditUpdate(
            value('$before$after', before.length),
            value('$before\n$after', before.length + 1),
          );

      expect(enter('- un').text, '- un\n- ');
      expect(enter('1. un').text, '1. un\n2. ');
      expect(
        enter('- [x] fait').text,
        '- [ ] fait\n- [ ] '.replaceFirst('- [ ] fait', '- [x] fait'),
      );
      expect(enter('  - sous').text, '  - sous\n  - ');
      // Empty item: the marker goes away and the list ends.
      final ended = enter('- un\n- ');
      expect(ended.text, '- un\n');
      expect(ended.selection.baseOffset, 5);
      // Plain text and mid-line Enter are untouched.
      expect(enter('texte').text, 'texte\n');
      // Splitting an item in two continues the list on the new line.
      expect(enter('- un', ' deux').text, startsWith('- un\n- '));
      // Typing a normal character does nothing special.
      expect(
        f.formatEditUpdate(value('- un', 4), value('- unx', 5)).text,
        '- unx',
      );
    });
  });

  group('document names and previews', () {
    test('title comes from the first readable line', () {
      expect(titleFor('# Courses du week-end\n- lait'), 'Courses du week-end');
      expect(
        titleFor('\n\n**Réunion** lundi: ordre/du jour'),
        'Réunion lundi ordre du jour',
      );
      expect(titleFor(''), 'Document');
      expect(titleFor('   \n  '), 'Document');
      expect(titleFor('a' * 80).length, 40);
    });

    test('preview skips the line that named the file', () {
      const text = '# Courses\n\nPenser à **tout** vérifier.\n- lait';
      expect(previewOf(text), 'Courses');
      expect(previewOf(text, title: 'Courses'), 'Penser à tout vérifier.');
      // A document whose title was edited keeps its first line.
      expect(previewOf(text, title: 'Autre nom'), 'Courses');
      // A one-line document has nothing else to show.
      expect(previewOf('# Seul', title: 'Seul'), 'Seul');
      expect(previewOf('', title: 'x'), '');
    });
  });

  group('text history', () {
    test('typing is merged, toolbar edits are separate steps', () {
      var clock = DateTime(2026);
      final c = TextEditingController();
      final h = TextHistory(c, now: () => clock);
      void type(String text) {
        c.value = value(text);
      }

      type('a');
      clock = clock.add(const Duration(milliseconds: 100));
      type('ab');
      clock = clock.add(const Duration(milliseconds: 100));
      type('abc'); // one burst
      expect(h.canUndo, true);
      clock = clock.add(const Duration(seconds: 2));
      type('abcd'); // a pause starts a new step

      h.undo();
      expect(c.text, 'abc');
      h.undo();
      expect(c.text, '');
      expect(h.canUndo, false);
      h.redo();
      expect(c.text, 'abc');
      h.redo();
      expect(c.text, 'abcd');
      expect(h.canRedo, false);

      // A formatting edit right after typing is undone on its own.
      c.value = value('abcd', 0, 4);
      h.checkpoint();
      c.value = toggleWrap(c.value, '**');
      h.checkpoint();
      expect(c.text, '**abcd**');
      h.undo();
      expect(c.text, 'abcd');

      // A new edit after undo drops the redo history.
      type('abcde');
      expect(h.canRedo, false);

      h.reset();
      expect(h.canUndo, false);
      h.dispose();
      c.dispose();
    });

    test('moving the caret is not an edit', () {
      final c = TextEditingController(text: 'abc');
      final h = TextHistory(c);
      c.selection = const TextSelection.collapsed(offset: 1);
      c.selection = const TextSelection.collapsed(offset: 2);
      expect(h.canUndo, false);
      h.dispose();
      c.dispose();
    });
  });
}
