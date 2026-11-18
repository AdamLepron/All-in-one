/// A match of a search in a text.
class TextMatch {
  const TextMatch(this.start, this.end);
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TextMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextMatch($start, $end)';
}

/// Every non-overlapping occurrence of [query] in [text]. Without
/// [caseSensitive] letters match whatever their case (accents still count);
/// with [wholeWord] only whole words match.
List<TextMatch> findAll(
  String text,
  String query, {
  bool caseSensitive = false,
  bool wholeWord = false,
}) {
  if (query.isEmpty) return const [];
  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  // Lower-casing can change the length of rare characters: then the
  // positions would no longer line up, so compare case-sensitively.
  if (haystack.length != text.length) {
    return findAll(text, query, caseSensitive: true, wholeWord: wholeWord);
  }
  bool isWord(String ch) =>
      RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(ch);
  final found = <TextMatch>[];
  var from = 0;
  while (true) {
    final i = haystack.indexOf(needle, from);
    if (i < 0) break;
    final end = i + needle.length;
    final alone =
        !wholeWord ||
        ((i == 0 || !isWord(text[i - 1])) &&
            (end == text.length || !isWord(text[end])));
    if (alone) {
      found.add(TextMatch(i, end));
      from = end;
    } else {
      from = i + 1;
    }
  }
  return found;
}

/// [text] with the occurrence [match] replaced by [replacement].
String replaceMatch(String text, TextMatch match, String replacement) =>
    text.replaceRange(match.start, match.end, replacement);

/// [text] with every occurrence replaced; also returns how many.
({String text, int count}) replaceEvery(
  String text,
  String query,
  String replacement, {
  bool caseSensitive = false,
  bool wholeWord = false,
}) {
  final matches = findAll(
    text,
    query,
    caseSensitive: caseSensitive,
    wholeWord: wholeWord,
  );
  if (matches.isEmpty) return (text: text, count: 0);
  final out = StringBuffer();
  var last = 0;
  for (final m in matches) {
    out
      ..write(text.substring(last, m.start))
      ..write(replacement);
    last = m.end;
  }
  out.write(text.substring(last));
  return (text: out.toString(), count: matches.length);
}

/// Index of the match to go to from [caret]: the first one starting at or
/// after it, wrapping around; with [backwards] the last one before it.
int nextMatchIndex(
  List<TextMatch> matches,
  int caret, {
  bool backwards = false,
}) {
  if (matches.isEmpty) return -1;
  if (backwards) {
    for (var i = matches.length - 1; i >= 0; i--) {
      if (matches[i].start < caret) return i;
    }
    return matches.length - 1;
  }
  for (var i = 0; i < matches.length; i++) {
    if (matches[i].start >= caret) return i;
  }
  return 0;
}
