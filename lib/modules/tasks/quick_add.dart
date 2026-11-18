/// Result of reading a line such as "appeler Paul demain 9h urgent".
class QuickTask {
  QuickTask(
    this.title,
    this.due,
    this.hasTime,
    this.priority, [
    this.labels = const [],
  ]);
  final String title;

  /// Words typed with a leading "#", without it.
  final List<String> labels;
  final DateTime? due;
  final bool hasTime;

  /// 0 none, 1 low, 2 medium, 3 high.
  final int priority;
}

const _weekdays = {
  'lundi': 1,
  'mardi': 2,
  'mercredi': 3,
  'jeudi': 4,
  'vendredi': 5,
  'samedi': 6,
  'dimanche': 7,
};

const _months = {
  'janvier': 1,
  'février': 2,
  'fevrier': 2,
  'mars': 3,
  'avril': 4,
  'mai': 5,
  'juin': 6,
  'juillet': 7,
  'août': 8,
  'aout': 8,
  'septembre': 9,
  'octobre': 10,
  'novembre': 11,
  'décembre': 12,
  'decembre': 12,
};

/// Extracts a date, a time and a priority from French free text; what is
/// left becomes the title.
QuickTask parseQuickTask(String input, DateTime now) {
  var text = ' ${input.trim()} ';
  final today = DateTime(now.year, now.month, now.day);
  DateTime? day;
  int? hour;
  var minute = 0;
  var priority = 0;

  /// Removes the first match of [pattern] and returns it.
  RegExpMatch? take(String pattern) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
    if (match != null) text = text.replaceRange(match.start, match.end, ' ');
    return match;
  }

  // Labels: "#maison"
  final labels = <String>[];
  for (final m in RegExp(
    r'(?<=\s)#([\p{L}\p{N}_-]+)(?=\s)',
    unicode: true,
  ).allMatches(text).toList()) {
    final label = m[1]!.toLowerCase();
    if (!labels.contains(label)) labels.add(label);
  }
  text = text.replaceAll(
    RegExp(r'(?<=\s)#[\p{L}\p{N}_-]+(?=\s)', unicode: true),
    ' ',
  );

  // Priority
  if (take(r'(?<=\s)(urgent|urgente|!!!)(?=\s)') != null) {
    priority = 3;
  } else if (take(r'(?<=\s)(important|importante|!!)(?=\s)') != null) {
    priority = 2;
  }

  // Time: "à 9h", "9h30", "14:30", "à midi"
  final clock = take(
    r"(?<=\s)(?:à\s+|a\s+)?(\d{1,2})\s?(?:h|:)\s?(\d{2})?(?=\s)",
  );
  if (clock != null && int.parse(clock[1]!) < 24) {
    hour = int.parse(clock[1]!);
    minute = int.tryParse(clock[2] ?? '') ?? 0;
    if (minute > 59) minute = 0;
  } else if (take(r'(?<=\s)(?:à\s+|a\s+)?midi(?=\s)') != null) {
    hour = 12;
  } else if (take(r'(?<=\s)(?:à\s+|a\s+)?minuit(?=\s)') != null) {
    hour = 0;
    day = today.add(const Duration(days: 1));
  }

  // Day
  RegExpMatch? m;
  if (take(r"(?<=\s)après[- ]demain(?=\s)") != null) {
    day = today.add(const Duration(days: 2));
  } else if (take(r'(?<=\s)demain(?=\s)') != null) {
    day = today.add(const Duration(days: 1));
  } else if (take(r"(?<=\s)(aujourd'hui|aujourd’hui)(?=\s)") != null) {
    day = today;
  } else if (take(r'(?<=\s)ce soir(?=\s)') != null) {
    day = today;
    hour ??= 19;
  } else if ((m = take(
        r'(?<=\s)dans\s+(\d{1,3})\s+(jours?|semaines?|mois)(?=\s)',
      )) !=
      null) {
    final n = int.parse(m![1]!);
    final unit = m[2]!.toLowerCase();
    day = unit.startsWith('jour')
        ? today.add(Duration(days: n))
        : unit.startsWith('semaine')
        ? today.add(Duration(days: 7 * n))
        : DateTime(today.year, today.month + n, today.day);
  } else if ((m = take(
        '(?<=\\s)(?:le\\s+)?(\\d{1,2})(?:er)?\\s+(${_months.keys.join('|')})(?:\\s+(\\d{4}))?(?=\\s)',
      )) !=
      null) {
    final month = _months[m![2]!.toLowerCase()]!;
    final year = int.tryParse(m[3] ?? '');
    var date = DateTime(year ?? today.year, month, int.parse(m[1]!));
    // A date already passed this year means next year.
    if (year == null && date.isBefore(today)) {
      date = DateTime(today.year + 1, month, int.parse(m[1]!));
    }
    day = date;
  } else if ((m = take(
        r'(?<=\s)(?:le\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{4}))?(?=\s)',
      )) !=
      null) {
    final d = int.parse(m![1]!);
    final month = int.parse(m[2]!);
    if (d >= 1 && d <= 31 && month >= 1 && month <= 12) {
      final year = int.tryParse(m[3] ?? '');
      var date = DateTime(year ?? today.year, month, d);
      if (year == null && date.isBefore(today)) {
        date = DateTime(today.year + 1, month, d);
      }
      day = date;
    }
  } else if ((m = take(
        '(?<=\\s)(${_weekdays.keys.join('|')})(?:\\s+prochain)?(?=\\s)',
      )) !=
      null) {
    final target = _weekdays[m![1]!.toLowerCase()]!;
    var ahead = (target - today.weekday) % 7;
    if (ahead == 0) ahead = 7; // "lundi" said on a Monday means next week
    day = today.add(Duration(days: ahead));
  }

  // A time alone means today, or tomorrow if that time has passed.
  if (day == null && hour != null) {
    final candidate = DateTime(
      today.year,
      today.month,
      today.day,
      hour,
      minute,
    );
    day = candidate.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  final title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final due = day == null
      ? null
      : DateTime(
          day.year,
          day.month,
          day.day,
          hour ?? 0,
          hour == null ? 0 : minute,
        );
  return QuickTask(title, due, hour != null, priority, labels);
}
