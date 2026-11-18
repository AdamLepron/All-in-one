import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:flutter/services.dart';

/// Wraps the selection in [open] and [close] (the same marker when null),
/// or removes them if they are already there. With nothing selected the
/// markers are inserted and the caret placed between them.
TextEditingValue toggleWrap(TextEditingValue v, String open, [String? close]) {
  close ??= open;
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final start = sel.start;
  final end = sel.end;
  final selected = text.substring(start, end);

  if (start != end &&
      selected.length >= open.length + close.length &&
      selected.startsWith(open) &&
      selected.endsWith(close)) {
    final inner = selected.substring(
      open.length,
      selected.length - close.length,
    );
    return TextEditingValue(
      text: text.replaceRange(start, end, inner),
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + inner.length,
      ),
    );
  }
  if (start >= open.length &&
      text.startsWith(open, start - open.length) &&
      text.startsWith(close, end)) {
    return TextEditingValue(
      text: text
          .replaceRange(end, end + close.length, '')
          .replaceRange(start - open.length, start, ''),
      selection: TextSelection(
        baseOffset: start - open.length,
        extentOffset: end - open.length,
      ),
    );
  }
  final wrapped = '$open$selected$close';
  return TextEditingValue(
    text: text.replaceRange(start, end, wrapped),
    selection: start == end
        ? TextSelection.collapsed(offset: start + open.length)
        : TextSelection(
            baseOffset: start + open.length,
            extentOffset: start + open.length + selected.length,
          ),
  );
}

final _anyPrefix = RegExp(
  r'^(#{1,6}\s+|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|>\s?)',
);

/// Start of the line containing [offset] and its end (before the newline).
(int, int) _lineAt(String text, int offset) {
  final from = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  final to = text.indexOf('\n', offset);
  return (from, to == -1 ? text.length : to);
}

/// Puts a prefix such as `- ` or `> ` at the start of every selected line,
/// replacing any other list or heading prefix. If every line already has
/// a prefix of the wanted kind ([same]) it is removed instead.
TextEditingValue toggleLinePrefix(
  TextEditingValue v, {
  required String Function(int index) prefix,
  required RegExp same,
}) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final (firstStart, _) = _lineAt(text, sel.start);
  // A selection ending just after a newline does not include the next line.
  final endOffset =
      sel.end > sel.start && sel.end > 0 && text[sel.end - 1] == '\n'
      ? sel.end - 1
      : sel.end;
  final (_, lastEnd) = _lineAt(text, endOffset);
  final lines = text.substring(firstStart, lastEnd).split('\n');
  final remove = lines.every((l) => same.hasMatch(l));

  var caretDelta = 0;
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final current = _anyPrefix.firstMatch(line)?.group(0) ?? '';
    final body = line.substring(current.length);
    final next = remove ? body : '${prefix(i)}$body';
    out.add(next);
    if (i == 0) caretDelta = next.length - line.length;
  }
  final replaced = out.join('\n');
  final newText = text.replaceRange(firstStart, lastEnd, replaced);
  if (sel.isCollapsed) {
    final offset = (sel.start + caretDelta).clamp(
      firstStart,
      firstStart + replaced.length,
    );
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
  return TextEditingValue(
    text: newText,
    selection: TextSelection(
      baseOffset: firstStart,
      extentOffset: firstStart + replaced.length,
    ),
  );
}

TextEditingValue toggleBullets(TextEditingValue v) => toggleLinePrefix(
  v,
  prefix: (_) => '- ',
  same: RegExp(r'^[-*+]\s+(?!\[[ xX]\])'),
);

TextEditingValue toggleNumbers(TextEditingValue v) => toggleLinePrefix(
  v,
  prefix: (i) => '${i + 1}. ',
  same: RegExp(r'^\d+[.)]\s+'),
);

TextEditingValue toggleChecklist(TextEditingValue v) => toggleLinePrefix(
  v,
  prefix: (_) => '- [ ] ',
  same: RegExp(r'^[-*+]\s+\[[ xX]\]\s+'),
);

TextEditingValue toggleQuote(TextEditingValue v) =>
    toggleLinePrefix(v, prefix: (_) => '> ', same: RegExp(r'^>\s?'));

/// Cycles the heading level of the current line: none, #, ##, ###, none.
TextEditingValue cycleHeading(TextEditingValue v) {
  final text = v.text;
  final offset = v.selection.isValid ? v.selection.start : text.length;
  final (from, to) = _lineAt(text, offset);
  final line = text.substring(from, to);
  final level = RegExp(r'^(#{1,3})\s').firstMatch(line)?.group(1)?.length ?? 0;
  final body = line.replaceFirst(_anyPrefix, '');
  final next = level >= 3 ? body : '${'#' * (level + 1)} $body';
  final newText = text.replaceRange(from, to, next);
  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: from + next.length),
  );
}

/// Inserts `[text](url)`, using the selection as the link text.
TextEditingValue insertLink(TextEditingValue v, String url) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final label = sel.isCollapsed ? 'lien' : text.substring(sel.start, sel.end);
  final link = '[$label]($url)';
  return TextEditingValue(
    text: text.replaceRange(sel.start, sel.end, link),
    selection: TextSelection.collapsed(offset: sel.start + link.length),
  );
}

TextEditingValue insertRule(TextEditingValue v) {
  final text = v.text;
  final offset = v.selection.isValid ? v.selection.end : text.length;
  final atLineStart = offset == 0 || text[offset - 1] == '\n';
  final insert = '${atLineStart ? '' : '\n'}\n---\n\n';
  return TextEditingValue(
    text: text.replaceRange(offset, offset, insert),
    selection: TextSelection.collapsed(offset: offset + insert.length),
  );
}

final _continuation = RegExp(
  r'^(\s*)([-*+] \[[ xX]\] |[-*+] |(\d+)([.)]) )(.*)$',
);

/// Pressing Enter at the end of a list item starts the next item; on an
/// empty item it ends the list.
class ListContinuation extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final caret = newValue.selection.baseOffset;
    final typedEnter =
        newValue.text.length == oldValue.text.length + 1 &&
        newValue.selection.isCollapsed &&
        caret > 0 &&
        newValue.text[caret - 1] == '\n' &&
        newValue.text.substring(0, caret - 1) +
                newValue.text.substring(caret) ==
            oldValue.text;
    if (!typedEnter) return newValue;

    final before = newValue.text.substring(0, caret - 1);
    final lineStart = before.lastIndexOf('\n') + 1;
    final m = _continuation.firstMatch(before.substring(lineStart));
    if (m == null) return newValue;

    if (m[5]!.trim().isEmpty) {
      // Empty item: remove its marker and leave the list.
      final cleared = newValue.text.replaceRange(lineStart, caret, '');
      return TextEditingValue(
        text: cleared,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    final marker = m[3] != null
        ? '${int.parse(m[3]!) + 1}${m[4]} '
        : m[2]!.contains('[')
        ? '${m[2]!.substring(0, 2)}[ ] '
        : m[2]!;
    final insert = '${m[1]}$marker';
    return TextEditingValue(
      text: newValue.text.replaceRange(caret, caret, insert),
      selection: TextSelection.collapsed(offset: caret + insert.length),
    );
  }
}

/// Undo and redo for a text field. Quick typing is merged into one step;
/// edits made by the toolbar are always steps of their own.
///
/// Flutter's built-in undo does not record programmatic edits, which is
/// what the formatting toolbar makes.
class TextHistory {
  TextHistory(
    this.controller, {
    DateTime Function()? now,
    this.pause = const Duration(milliseconds: 700),
  }) : _now = now ?? DateTime.now,
       _prev = controller.value {
    controller.addListener(_onChanged);
  }

  final TextEditingController controller;
  final Duration pause;
  final DateTime Function() _now;
  final _undo = <TextEditingValue>[];
  final _redo = <TextEditingValue>[];
  TextEditingValue _prev;
  DateTime _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _forceNew = true;
  bool _applying = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _onChanged() {
    if (_applying) return;
    final value = controller.value;
    if (value.text == _prev.text) {
      _prev = value; // selection moved only
      return;
    }
    final now = _now();
    if (_forceNew || now.difference(_lastEdit) > pause) _undo.add(_prev);
    _forceNew = false;
    _lastEdit = now;
    _redo.clear();
    _prev = value;
  }

  /// The next change starts a new undo step, whatever the time elapsed.
  void checkpoint() => _forceNew = true;

  /// Forgets everything, for example after loading a file.
  void reset() {
    _undo.clear();
    _redo.clear();
    _prev = controller.value;
    _forceNew = true;
  }

  void _restore(TextEditingValue value) {
    _applying = true;
    controller.value = value;
    _applying = false;
    _prev = value;
    _forceNew = true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(controller.value);
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(controller.value);
    _restore(_redo.removeLast());
  }

  void dispose() => controller.removeListener(_onChanged);
}

/// Inserts an empty table of [columns] × [rows] (plus the header) at the
/// caret, on its own lines.
TextEditingValue insertTable(
  TextEditingValue v, {
  int columns = 2,
  int rows = 2,
}) {
  final cols = columns.clamp(1, 8);
  final body = rows.clamp(1, 30);
  String line(String Function(int) cell) =>
      '| ${[for (var c = 0; c < cols; c++) cell(c)].join(' | ')} |';
  final table = [
    line((c) => 'Colonne ${c + 1}'),
    line((_) => '---'),
    for (var r = 0; r < body; r++) line((_) => '   '),
  ].join('\n');
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: v.text.length);
  final before = v.text.substring(0, sel.start);
  final after = v.text.substring(sel.end);
  // A blank line before and after keeps the table apart from other text.
  final lead = before.isEmpty || before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final tail = after.startsWith('\n\n') || after.isEmpty ? '\n' : '\n\n';
  final text = '$before$lead$table$tail$after';
  return TextEditingValue(
    text: text,
    // The caret goes to the first header cell, selecting its placeholder.
    selection: TextSelection(
      baseOffset: before.length + lead.length + 2,
      extentOffset: before.length + lead.length + 2 + 'Colonne 1'.length,
    ),
  );
}

/// Inserts `![alt](src)` on its own line at the caret.
TextEditingValue insertImage(TextEditingValue v, String alt, String src) {
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: v.text.length);
  final before = v.text.substring(0, sel.start);
  final after = v.text.substring(sel.end);
  final safeAlt = alt.replaceAll(RegExp(r'[\[\]\n]'), ' ').trim();
  final safeSrc = src.replaceAll(' ', '%20').replaceAll(')', '%29');
  final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
  final tail = after.isEmpty || after.startsWith('\n') ? '' : '\n';
  final insert = '$lead![$safeAlt]($safeSrc)$tail';
  return TextEditingValue(
    text: '$before$insert$after',
    selection: TextSelection.collapsed(offset: before.length + insert.length),
  );
}
