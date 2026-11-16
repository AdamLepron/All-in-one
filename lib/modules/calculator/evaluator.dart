import 'dart:math' as math;

/// Evaluates an arithmetic expression as typed on the calculator keypad.
///
/// Supports + − × ÷ ^ % !, parentheses, implicit multiplication ("2π",
/// "3(4+1)"), the constants π and e, and sin cos tan ln log √. Unclosed
/// parentheses are closed automatically. Throws [FormatException] on a
/// malformed expression.
double evaluate(String expression, {bool degrees = true}) {
  final parser = _Parser(expression, degrees);
  final value = parser.expression();
  if (!parser.atEnd) throw const FormatException('Unexpected input');
  return value;
}

const _functions = ['sin', 'cos', 'tan', 'ln', 'log', '√'];

class _Parser {
  _Parser(String source, this.degrees)
    : src = source
          .replaceAll(' ', '')
          .replaceAll(' ', '')
          .replaceAll(',', '.')
          .replaceAll('−', '-');

  final String src;
  final bool degrees;
  int pos = 0;

  bool get atEnd => pos >= src.length;
  String get peek => atEnd ? '' : src[pos];

  bool eat(String s) {
    if (src.startsWith(s, pos)) {
      pos += s.length;
      return true;
    }
    return false;
  }

  double expression() {
    var value = term();
    while (true) {
      if (eat('+')) {
        value += term();
      } else if (eat('-')) {
        value -= term();
      } else {
        return value;
      }
    }
  }

  double term() {
    var value = factor();
    while (true) {
      if (eat('×') || eat('*')) {
        value *= factor();
      } else if (eat('÷') || eat('/')) {
        value /= factor();
      } else if (startsPrimary) {
        value *= factor(); // implicit multiplication
      } else {
        return value;
      }
    }
  }

  bool get startsPrimary {
    if (atEnd) return false;
    final c = peek;
    return c == '(' ||
        c == 'π' ||
        c == 'e' ||
        _isDigit(c) ||
        _functions.any((f) => src.startsWith(f, pos));
  }

  double factor() {
    if (eat('-')) return -factor();
    final base = postfix();
    if (eat('^')) return math.pow(base, factor()).toDouble();
    return base;
  }

  double postfix() {
    var value = primary();
    while (true) {
      if (eat('%')) {
        value /= 100;
      } else if (eat('!')) {
        value = _factorial(value);
      } else {
        return value;
      }
    }
  }

  double primary() {
    if (eat('(')) {
      final value = expression();
      if (!eat(')') && !atEnd) throw const FormatException('Missing )');
      return value;
    }
    if (eat('π')) return math.pi;
    for (final f in _functions) {
      if (eat(f)) {
        // "√9" is allowed without parentheses.
        final arg = peek == '(' ? primary() : factor();
        return _apply(f, arg);
      }
    }
    if (eat('e')) return math.e;
    final start = pos;
    while (!atEnd && (_isDigit(peek) || peek == '.')) {
      pos++;
    }
    if (start == pos) throw const FormatException('Number expected');
    return double.parse(src.substring(start, pos));
  }

  double _apply(String f, double x) {
    final rad = degrees ? x * math.pi / 180 : x;
    switch (f) {
      case 'sin':
        return _clean(math.sin(rad));
      case 'cos':
        return _clean(math.cos(rad));
      case 'tan':
        return _clean(math.cos(rad)) == 0 ? double.nan : _clean(math.tan(rad));
      case 'ln':
        return math.log(x);
      case 'log':
        return math.log(x) / math.ln10;
      default:
        return math.sqrt(x);
    }
  }

  /// Rounds floating-point noise such as sin(180°) = 1.2e-16 to zero.
  static double _clean(double v) => v.abs() < 1e-12 ? 0 : v;

  static double _factorial(double n) {
    if (n < 0 || n != n.roundToDouble() || n > 170) return double.nan;
    var result = 1.0;
    for (var i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 48 && u <= 57;
  }
}
