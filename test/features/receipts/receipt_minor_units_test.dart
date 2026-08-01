import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_minor_units.dart';

/// The money boundary: what a person types, and the integer that reaches
/// `bigint`.
///
/// The one rule these tests exist to defend is that **no monetary value is ever
/// a `double`**. Every expectation below is an `int`, and the values chosen are
/// the ones a floating-point conversion gets wrong: `19.99 * 100` is
/// `1998.9999999999998` in IEEE-754, so a build that multiplied would fail here
/// rather than in somebody's reward calculation a milestone later.
void main() {
  group('parsing an amount into integer minor units', () {
    test('an ordinary two-decimal amount', () {
      expect(parseMinorUnits('125.50', 2), isA<MinorUnitValue>());
      expect((parseMinorUnits('125.50', 2) as MinorUnitValue).minor, 12550);
    });

    test('the values a double would get wrong', () {
      // Each of these is a value where `x * 100` is not exact in binary
      // floating point. The parse is string work, so every one is exact.
      const Map<String, int> cases = <String, int>{
        '19.99': 1999,
        '0.29': 29,
        '1.15': 115,
        '8.20': 820,
        '70.70': 7070,
        '1234.56': 123456,
      };
      cases.forEach((String text, int expected) {
        final MinorUnitResult result = parseMinorUnits(text, 2);
        expect(result, isA<MinorUnitValue>(), reason: text);
        expect((result as MinorUnitValue).minor, expected, reason: text);
      });
    });

    test('a whole number takes the currency width', () {
      expect((parseMinorUnits('125', 2) as MinorUnitValue).minor, 12500);
      expect((parseMinorUnits('125', 0) as MinorUnitValue).minor, 125);
      expect((parseMinorUnits('125', 3) as MinorUnitValue).minor, 125000);
    });

    test('a short fraction is padded, not truncated', () {
      expect((parseMinorUnits('125.5', 2) as MinorUnitValue).minor, 12550);
      expect((parseMinorUnits('1.5', 3) as MinorUnitValue).minor, 1500);
    });

    test('a comma is the same separator as a point', () {
      expect((parseMinorUnits('125,50', 2) as MinorUnitValue).minor, 12550);
    });

    test('both separators together are refused, never guessed', () {
      // `1,234.56` and `1.234,56` are different amounts and this application
      // carries no locale to tell them apart.
      expect(
        (parseMinorUnits('1,234.56', 2) as MinorUnitRefusal).problem,
        MinorUnitProblem.notANumber,
      );
    });

    test('a leading separator is read as zero-point-something', () {
      expect((parseMinorUnits('.50', 2) as MinorUnitValue).minor, 50);
    });

    test('zero is a real total', () {
      expect((parseMinorUnits('0', 2) as MinorUnitValue).minor, 0);
      expect((parseMinorUnits('0.00', 2) as MinorUnitValue).minor, 0);
    });

    test('surrounding spaces are ignored', () {
      expect((parseMinorUnits('  12.30 ', 2) as MinorUnitValue).minor, 1230);
    });

    test('an empty field is refused as empty, not as a zero', () {
      expect(
        (parseMinorUnits('', 2) as MinorUnitRefusal).problem,
        MinorUnitProblem.empty,
      );
      expect(
        (parseMinorUnits('   ', 2) as MinorUnitRefusal).problem,
        MinorUnitProblem.empty,
      );
    });

    test('too many decimals is refused rather than rounded', () {
      expect(
        (parseMinorUnits('1.234', 2) as MinorUnitRefusal).problem,
        MinorUnitProblem.tooPrecise,
      );
      expect(
        (parseMinorUnits('1.5', 0) as MinorUnitRefusal).problem,
        MinorUnitProblem.tooPrecise,
      );
    });

    test('anything that is not a plain amount is refused', () {
      for (final String text in <String>[
        'abc',
        '12abc',
        '1.2.3',
        r'$12.00',
        '12 34',
        '1e3',
        '.',
      ]) {
        expect(parseMinorUnits(text, 2), isA<MinorUnitRefusal>(), reason: text);
      }
    });

    test('a negative amount is refused — there is no minus sign here', () {
      expect(parseMinorUnits('-1.00', 2), isA<MinorUnitRefusal>());
    });

    test('the 10^12 ceiling is inclusive and one above it is refused', () {
      expect(
        (parseMinorUnits('10000000000.00', 2) as MinorUnitValue).minor,
        1000000000000,
      );
      expect(
        (parseMinorUnits('10000000000.01', 2) as MinorUnitRefusal).problem,
        MinorUnitProblem.outOfRange,
      );
    });
  });

  group('formatting minor units back into text', () {
    test('round-trips through the parser exactly', () {
      for (final int minor in <int>[0, 1, 29, 999, 12550, 1000000000000]) {
        final String text = formatMinorUnits(minor, 2);
        expect(
          (parseMinorUnits(text, 2) as MinorUnitValue).minor,
          minor,
          reason: text,
        );
      }
    });

    test('pads a value narrower than the currency', () {
      expect(formatMinorUnits(5, 2), '0.05');
      expect(formatMinorUnits(50, 2), '0.50');
      expect(formatMinorUnits(5, 3), '0.005');
    });

    test('a zero-decimal currency keeps its integer intact', () {
      expect(formatMinorUnits(12550, 0), '12550');
    });

    test('the amount carries its ISO code and never a symbol', () {
      expect(formatMinorAmount(12550, 'AED', 2), 'AED 125.50');
      expect(formatMinorAmount(12550, null, 2), '125.50');
      expect(formatMinorAmount(12550, '  ', 2), '125.50');
    });
  });

  group('the four widths, on the amounts they scale', () {
    // The blocking defect this correction removes, stated as arithmetic. Each
    // of these is what a two-decimal assumption used to get wrong.
    test('JPY 1000 is 1000 minor units, not 100000', () {
      expect((parseMinorUnits('1000', 0) as MinorUnitValue).minor, 1000);
    });

    test('EUR 12.34 is 1234 minor units', () {
      expect((parseMinorUnits('12.34', 2) as MinorUnitValue).minor, 1234);
    });

    test('KWD 1.234 is 1234 minor units', () {
      expect((parseMinorUnits('1.234', 3) as MinorUnitValue).minor, 1234);
    });

    test('CLF 1.2345 is 12345 minor units', () {
      expect((parseMinorUnits('1.2345', 4) as MinorUnitValue).minor, 12345);
    });

    test('a fraction a zero-decimal currency cannot carry is refused', () {
      // Refused rather than rounded to 1: dropping the digit changes the figure
      // somebody entered, and ¥1.1 is not a receipt total this system records.
      expect(
        (parseMinorUnits('1.1', 0) as MinorUnitRefusal).problem,
        MinorUnitProblem.tooPrecise,
      );
    });

    test('a fourth decimal on a three-decimal currency is refused', () {
      expect(
        (parseMinorUnits('1.2345', 3) as MinorUnitRefusal).problem,
        MinorUnitProblem.tooPrecise,
      );
    });

    test('a fifth decimal on a four-decimal currency is refused', () {
      expect(
        (parseMinorUnits('1.23456', 4) as MinorUnitRefusal).problem,
        MinorUnitProblem.tooPrecise,
      );
    });

    test('a third decimal on a two-decimal currency is refused', () {
      expect(
        (parseMinorUnits('12.345', 2) as MinorUnitRefusal).problem,
        MinorUnitProblem.tooPrecise,
      );
    });
  });

  group('this module has no opinion about any currency', () {
    test('every conversion takes its width as an argument', () {
      // There is no `minorDigitsFor`, no `defaultMinorDigits` and no ISO map:
      // the width is the backend's answer, and a function that could produce
      // one without being told is the defect this correction removed. The two
      // assertions below are the same amount under two widths, which is only
      // expressible because neither is this module's choice.
      expect((parseMinorUnits('1000', 0) as MinorUnitValue).minor, 1000);
      expect((parseMinorUnits('1000', 2) as MinorUnitValue).minor, 100000);
    });

    test('formatting takes its width too', () {
      expect(formatMinorUnits(1000, 0), '1000');
      expect(formatMinorUnits(1000, 2), '10.00');
      expect(formatMinorUnits(1234, 3), '1.234');
      expect(formatMinorUnits(12345, 4), '1.2345');
    });
  });
}
