import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/money.dart';

void main() {
  group('Money', () {
    test('parses API strings exactly', () {
      expect(Money.parse('450000.00').minor, BigInt.from(45000000));
      expect(Money.parse('0.1').toApi(), '0.10');
      expect(Money.parse('-12.30').toApi(), '-12.30');
      expect(Money.parse('1,250,000').toApi(), '1250000.00');
      expect(() => Money.parse('1.234'), throwsFormatException);
      expect(() => Money.parse('abc'), throwsFormatException);
      expect(Money.tryParse(''), isNull);
    });

    test('has no floating point drift', () {
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total = total + Money.parse('0.10');
      }
      expect(total, Money.parse('1.00'));
    });

    test('formats UGX without needless decimals', () {
      expect(Money.parse('1250000').format('UGX'), 'UGX 1,250,000');
      expect(Money.parse('99.5').format('USD'), 'USD 99.50');
      expect(Money.parse('-500').format('UGX'), '-UGX 500');
      expect(Money.parse('15000').format('UGX', showCurrency: false), '15,000');
    });

    test('multiplies by fractional quantities with half-up rounding', () {
      expect(Money.parse('15000').times(Quantity.parse('3')), Money.parse('45000'));
      expect(Money.parse('1000').times(Quantity.parse('1.5')), Money.parse('1500'));
      expect(Money.parse('0.10').times(Quantity.parse('0.333')), Money.parse('0.03'));
      expect(Money.parse('0.15').times(Quantity.parse('0.1')), Money.parse('0.02'));
    });
  });

  group('Quantity', () {
    test('round-trips without trailing zeros', () {
      expect(Quantity.parse('5').toString(), '5');
      expect(Quantity.parse('2.500').toString(), '2.5');
      expect(Quantity.parse('-1.5').toString(), '-1.5');
      expect((Quantity.parse('1.25') + Quantity.parse('0.75')).toString(), '2');
    });
  });
}
