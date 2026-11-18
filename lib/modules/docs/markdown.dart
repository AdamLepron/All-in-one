import 'dart:io';

import 'package:path/path.dart' as p;

/// Minimal Markdown: headings, paragraphs, lists (bulleted, numbered,
/// checklists), quotes, code blocks, rules, and inline bold, italic,
/// strike-through, code and links.
sealed class Block {
  const Block();
}

class Heading extends Block {
  const Heading(this.level, this.text);
  final int level;
  final String text;
}

class Paragraph extends Block {
  const Paragraph(this.text);
  final String text;
}

class ListItem extends Block {
  const ListItem(this.text, {this.indent = 0, this.number, this.checked});
  final String text;

  /// Nesting level: two spaces of indentation per level.
  final int indent;

  /// Set for numbered items.
  final int? number;

  /// Set for checklist items.
  final bool? checked;
}

class Quote extends Block {
  const Quote(this.text);
  final String text;
}

class CodeBlock extends Block {
  const CodeBlock(this.code);
  final String code;
}

class Rule extends Block {
  const Rule();
}

/// A picture on its own line: `![description](path)`.
class ImageBlock extends Block {
  const ImageBlock(this.alt, this.src);
  final String alt;
  final String src;
}

enum CellAlign { left, center, right }

/// A table: a header row, then rows. Every row has as many cells as the
/// header.
class TableBlock extends Block {
  const TableBlock(this.header, this.rows, this.aligns);
  final List<String> header;
  final List<List<String>> rows;
  final List<CellAlign> aligns;
}

final _image = RegExp(r'^\s*!\[([^\]\n]*)\]\(([^)\n]+)\)\s*$');
final _tableSeparator = RegExp(
  r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$',
);

/// Cells of one table row, without the outer pipes. "\|" is a literal bar.
List<String> splitRow(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|') && !t.endsWith(r'\|')) t = t.substring(0, t.length - 1);
  final cells = <String>[];
  final cell = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    if (t[i] == r'\' && i + 1 < t.length && t[i + 1] == '|') {
      cell.write('|');
      i++;
    } else if (t[i] == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(t[i]);
    }
  }
  cells.add(cell.toString().trim());
  return cells;
}

final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final _quote = RegExp(r'^>\s?(.*)$');
final _check = RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _ordered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');

/// Parses [source] into blocks. Never throws: anything unrecognised is a
/// paragraph.
List<Block> parseMarkdown(String source) {
  final blocks = <Block>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  var paragraph = <String>[];
  var quote = <String>[];
  var inCode = false;
  final code = <String>[];

  void flush() {
    if (paragraph.isNotEmpty) blocks.add(Paragraph(paragraph.join('\n')));
    if (quote.isNotEmpty) blocks.add(Quote(quote.join('\n')));
    paragraph = [];
    quote = [];
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (!inCode &&
        line.contains('|') &&
        index + 1 < lines.length &&
        lines[index + 1].contains('-') &&
        lines[index + 1].contains('|') &&
        _tableSeparator.hasMatch(lines[index + 1])) {
      final header = splitRow(line);
      final marks = splitRow(lines[index + 1]);
      // The separator must have as many columns as the header.
      if (marks.length == header.length) {
        flush();
        final rows = <List<String>>[];
        var next = index + 2;
        while (next < lines.length &&
            lines[next].trim().isNotEmpty &&
            lines[next].contains('|')) {
          final cells = splitRow(lines[next]);
          // Short rows are completed, long ones cut.
          rows.add([
            for (var c = 0; c < header.length; c++)
              c < cells.length ? cells[c] : '',
          ]);
          next++;
        }
        blocks.add(
          TableBlock(header, rows, [
            for (final m in marks)
              m.startsWith(':') && m.endsWith(':')
                  ? CellAlign.center
                  : m.endsWith(':')
                  ? CellAlign.right
                  : CellAlign.left,
          ]),
        );
        index = next - 1;
        continue;
      }
    }
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        blocks.add(CodeBlock(code.join('\n')));
        code.clear();
      } else {
        flush();
      }
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      code.add(line);
      continue;
    }
    RegExpMatch? m;
    if (line.trim().isEmpty) {
      flush();
    } else if ((m = _image.firstMatch(line)) != null) {
      flush();
      blocks.add(ImageBlock(m![1]!.trim(), m[2]!.trim()));
    } else if ((m = _heading.firstMatch(line)) != null) {
      flush();
      blocks.add(Heading(m![1]!.length, m[2]!.trim()));
    } else if (_rule.hasMatch(line)) {
      flush();
      blocks.add(const Rule());
    } else if ((m = _quote.firstMatch(line)) != null) {
      if (paragraph.isNotEmpty) flush();
      quote.add(m![1]!);
    } else if ((m = _check.firstMatch(line)) != null) {
      flush();
      blocks.add(
        ListItem(m![3]!, indent: m[1]!.length ~/ 2, checked: m[2] != ' '),
      );
    } else if ((m = _bullet.firstMatch(line)) != null) {
      flush();
      blocks.add(ListItem(m![2]!, indent: m[1]!.length ~/ 2));
    } else if ((m = _ordered.firstMatch(line)) != null) {
      flush();
      blocks.add(
        ListItem(m![3]!, indent: m[1]!.length ~/ 2, number: int.parse(m[2]!)),
      );
    } else {
      if (quote.isNotEmpty) flush();
      paragraph.add(line);
    }
  }
  if (inCode) blocks.add(CodeBlock(code.join('\n'))); // unclosed fence
  flush();
  return blocks;
}

/// A run of text sharing the same style.
class Span {
  const Span(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? link;

  Span copyWith({bool? bold, bool? italic, bool? strike, String? link}) => Span(
    text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strike: strike ?? this.strike,
    code: code,
    link: link ?? this.link,
  );

  @override
  bool operator ==(Object other) =>
      other is Span &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.strike == strike &&
      other.code == code &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, bold, italic, strike, code, link);

  @override
  String toString() =>
      'Span($text${bold ? ' b' : ''}${italic ? ' i' : ''}${strike ? ' s' : ''}${code ? ' c' : ''}${link != null ? ' →$link' : ''})';
}

final _inline = RegExp(
  r'`([^`\n]+)`' // 1 code
  r'|\*\*(.+?)\*\*(?!\*)' // 2 bold
  r'|~~(.+?)~~' // 3 strike
  r'|\*(?!\s)(.+?)(?<!\s)\*' // 4 italic
  r'|(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)' // 5 italic
  r'|\[([^\]\n]+)\]\(([^)\s]+)\)', // 6 link text, 7 url
);

/// Splits one block's text into styled runs.
List<Span> parseInline(String text) {
  final spans = <Span>[];
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > last) spans.add(Span(text.substring(last, m.start)));
    if (m[1] != null) {
      spans.add(Span(m[1]!, code: true));
    } else if (m[2] != null) {
      spans.addAll([
        for (final s in parseInline(m[2]!)) s.copyWith(bold: true),
      ]);
    } else if (m[3] != null) {
      spans.addAll([
        for (final s in parseInline(m[3]!)) s.copyWith(strike: true),
      ]);
    } else if (m[4] != null || m[5] != null) {
      spans.addAll([
        for (final s in parseInline((m[4] ?? m[5])!)) s.copyWith(italic: true),
      ]);
    } else {
      spans.addAll([
        for (final s in parseInline(m[6]!)) s.copyWith(link: m[7]),
      ]);
    }
    last = m.end;
  }
  if (last < text.length) spans.add(Span(text.substring(last)));
  return spans;
}

/// Words and characters of the text as the author wrote it.
({int words, int characters}) textStats(String text) =>
    (words: RegExp(r'\S+').allMatches(text).length, characters: text.length);

/// The file an image block points to: an absolute path, or one relative to
/// [baseDir] (the document's folder). Web addresses are never fetched, and
/// null is returned when the file does not exist.
File? resolveImage(String src, String? baseDir) {
  final scheme = Uri.tryParse(src)?.scheme ?? '';
  if (scheme.isNotEmpty &&
      scheme != 'file' &&
      !RegExp(r'^[A-Za-z]$').hasMatch(scheme)) {
    return null;
  }
  var path = scheme == 'file' ? Uri.parse(src).toFilePath() : src;
  try {
    path = Uri.decodeFull(path);
  } on Object {
    // Not percent-encoded after all: used as written.
  }
  if (p.isRelative(path)) {
    if (baseDir == null) return null;
    path = p.join(baseDir, path);
  }
  final file = File(path);
  return file.existsSync() ? file : null;
}
