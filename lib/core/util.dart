const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Short French date relative to now: "À l'instant", "Il y a 5 min",
/// "Aujourd'hui 14:05", "Hier 09:30", "12 mars", "12 mars 2024".
String relativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inSeconds < 60) return "À l'instant";
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  final time = '${_two(date.hour)}:${_two(date.minute)}';
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (days == 0) return "Aujourd'hui $time";
  if (days == 1) return 'Hier $time';
  final day = '${date.day} ${_months[date.month - 1]}';
  return date.year == now.year ? day : '$day ${date.year}';
}

/// Formats a number for display: French decimal comma, thin grouping of
/// thousands, at most [digits] significant digits, no trailing zeros.
String formatNumber(double value, {int digits = 10}) {
  if (value.isNaN) return 'Erreur';
  if (value.isInfinite) return value > 0 ? '∞' : '-∞';
  if (value == 0) return '0';
  final abs = value.abs();
  if (abs >= 1e15 || abs < 1e-9) {
    // "1,5×10^21" rather than "1.5e+21": readable, and the calculator can
    // parse it back.
    final parts = value.toStringAsExponential(6).split('e');
    final mantissa = parts[0]
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
    return '$mantissa×10^${int.parse(parts[1])}';
  }
  var s = value.toStringAsPrecision(digits);
  if (s.contains('e')) s = value.toStringAsFixed(0);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  final parts = s.split('.');
  final negative = parts[0].startsWith('-');
  final intPart = negative ? parts[0].substring(1) : parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$buffer${parts.length > 1 ? ',${parts[1]}' : ''}';
}

/// "1,4 Go", "512 ko", "0 o".
String formatBytes(int bytes) {
  const units = ['o', 'ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

/// "3:07", "1:02:45".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = _two(d.inSeconds.remainder(60));
  return h > 0 ? '$h:${_two(m)}:$s' : '$m:$s';
}

const _fullMonths = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Heading for a day in a timeline: "Aujourd'hui", "Hier", "12 mars",
/// "12 mars 2024".
String dayLabel(DateTime date) {
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (days == 0) return "Aujourd'hui";
  if (days == 1) return 'Hier';
  final day = '${date.day} ${_fullMonths[date.month - 1]}';
  return date.year == now.year ? day : '$day ${date.year}';
}

/// "12 mars 2024 à 14:05".
String fullDate(DateTime date) =>
    '${date.day} ${_fullMonths[date.month - 1]} ${date.year} à ${_two(date.hour)}:${_two(date.minute)}';

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// "lundi 16 novembre".
String dayLabelLong(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} ${_fullMonths[date.month - 1]}';
