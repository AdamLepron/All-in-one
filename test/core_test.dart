import 'package:all_in_one/core/util.dart';
import 'package:all_in_one/modules/calculator/evaluator.dart';
import 'package:all_in_one/modules/converter/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evaluator', () {
    expect(evaluate('2+3×4'), 14);
    expect(evaluate('(2+3)×4'), 20);
    expect(evaluate('−5+2'), -3);
    expect(evaluate('2^3^2'), 512);
    expect(evaluate('50%'), 0.5);
    expect(evaluate('2π'), closeTo(6.2831853, 1e-6));
    expect(evaluate('3(4+1'), 15);
    expect(evaluate('√9+5!'), 123);
    expect(evaluate('sin(30)'), closeTo(0.5, 1e-12));
    expect(evaluate('sin(180)'), 0);
    expect(evaluate('1,5×2'), 3);
    expect(evaluate('1,5×10^-3'), closeTo(0.0015, 1e-12));
    expect(evaluate('1÷0').isInfinite, true);
    expect(() => evaluate('2+'), throwsFormatException);
    expect(() => evaluate('×2'), throwsFormatException);
  });

  test('formatNumber', () {
    expect(formatNumber(1234567.5), '1 234 567,5');
    expect(formatNumber(0.1 + 0.2), '0,3');
    expect(formatNumber(-1000), '-1 000');
    expect(formatNumber(1.5e21), '1,5×10^21');
    expect(formatNumber(123456789012), '123 456 789 012');
  });

  test('unit conversion', () {
    final temp = unitCategories.firstWhere((c) => c.name == 'Température').units;
    expect(convert(100, temp[0], temp[1]), closeTo(212, 1e-9));
    expect(convert(32, temp[1], temp[0]), closeTo(0, 1e-9));
    final len = unitCategories.first.units;
    expect(convert(1, len[1], len[0]), 1000);
  });
}
