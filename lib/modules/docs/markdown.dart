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

  for (final line in lines) {
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
