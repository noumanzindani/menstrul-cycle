import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

/// Height mirrors weight: canonical centimetres are stored, the display unit is
/// applied only at the boundary, and anything blank/garbage/out-of-range is a
/// REFUSAL (null) rather than a silent clamp.
///
/// The unit argument is the EXISTING weight-unit preference — kg means
/// centimetres, lb means feet + inches — so there is no second unit column.
void main() {
  group('height unit conversion', () {
    test('inch <-> cm round-trips within a rounding tolerance', () {
      expect(inchToCm(65), closeTo(165.1, 0.001));
      expect(cmToInch(165.1), closeTo(65, 0.001));
      expect(cmToInch(inchToCm(70)), closeTo(70, 0.001));
    });

    test('uses exactly 2.54 cm per inch', () {
      expect(inchToCm(1), closeTo(2.54, 1e-12));
    });
  });

  group('parseHeightToCm in cm (kg preference)', () {
    test('parses a cm value as-is', () {
      expect(parseHeightToCm('165', kWeightUnitKg), closeTo(165, 0.001));
      expect(parseHeightToCm('165.5', kWeightUnitKg), closeTo(165.5, 0.001));
    });

    test('tolerates surrounding whitespace', () {
      expect(parseHeightToCm('  165  ', kWeightUnitKg), closeTo(165, 0.001));
    });

    test('returns null for blank or unparseable input', () {
      expect(parseHeightToCm('', kWeightUnitKg), isNull);
      expect(parseHeightToCm('   ', kWeightUnitKg), isNull);
      expect(parseHeightToCm('tall', kWeightUnitKg), isNull);
    });

    test('refuses values outside 80-250 cm', () {
      expect(parseHeightToCm('79.9', kWeightUnitKg), isNull);
      expect(parseHeightToCm('250.1', kWeightUnitKg), isNull);
      expect(parseHeightToCm('0', kWeightUnitKg), isNull);
      expect(parseHeightToCm('-165', kWeightUnitKg), isNull);
    });

    test('accepts the exact boundaries', () {
      expect(parseHeightToCm('80', kWeightUnitKg), closeTo(80, 0.001));
      expect(parseHeightToCm('250', kWeightUnitKg), closeTo(250, 0.001));
    });
  });

  group('parseHeightToCm in feet+inches (lb preference)', () {
    test("parses 5'5\" into canonical cm", () {
      expect(parseHeightToCm("5'5\"", kWeightUnitLb), closeTo(165.1, 0.01));
    });

    test('accepts the readable variants of the same height', () {
      for (final input in ["5'5", "5' 5\"", "5 ' 5 \"", '5ft 5in', '5 FT 5 IN']) {
        expect(parseHeightToCm(input, kWeightUnitLb), closeTo(165.1, 0.01),
            reason: 'should parse $input');
      }
    });

    test('accepts whole feet with no inches', () {
      expect(parseHeightToCm("5'", kWeightUnitLb), closeTo(152.4, 0.01));
    });

    test('parses a bare number as inches', () {
      expect(parseHeightToCm('65', kWeightUnitLb), closeTo(165.1, 0.01));
    });

    test('returns null for blank or unparseable input', () {
      expect(parseHeightToCm('', kWeightUnitLb), isNull);
      expect(parseHeightToCm('   ', kWeightUnitLb), isNull);
      expect(parseHeightToCm('five foot five', kWeightUnitLb), isNull);
      expect(parseHeightToCm("''", kWeightUnitLb), isNull);
    });

    test('applies the range AFTER converting to cm', () {
      // 2'7" == 78.7 cm, below the minimum despite looking like a small number.
      expect(parseHeightToCm("2'7\"", kWeightUnitLb), isNull);
      // 8'3" == 251.5 cm, above the maximum.
      expect(parseHeightToCm("8'3\"", kWeightUnitLb), isNull);
      // A bare 165 read as INCHES is 419 cm — refused, not silently taken as cm.
      expect(parseHeightToCm('165', kWeightUnitLb), isNull);
    });

    test('accepts the values just inside the converted boundaries', () {
      // 2'8" == 81.3 cm, 8'2" == 248.9 cm.
      expect(parseHeightToCm("2'8\"", kWeightUnitLb), closeTo(81.28, 0.01));
      expect(parseHeightToCm("8'2\"", kWeightUnitLb), closeTo(248.92, 0.01));
      // The same rule on bare inches: 31.5in == 80.0 cm, 31.4in == 79.8 cm.
      expect(parseHeightToCm('31.5', kWeightUnitLb), closeTo(80.01, 0.01));
      expect(parseHeightToCm('31.4', kWeightUnitLb), isNull);
    });
  });

  group('formatHeightFromCm', () {
    test('formats cm to one decimal, rounding', () {
      expect(formatHeightFromCm(165.04, kWeightUnitKg), '165.0');
      expect(formatHeightFromCm(172.46, kWeightUnitKg), '172.5');
    });

    test('emits no unit suffix — the field draws it', () {
      expect(formatHeightFromCm(165, kWeightUnitKg), '165.0');
    });

    test('formats cm as feet and inches', () {
      expect(formatHeightFromCm(165.1, kWeightUnitLb), "5'5\"");
      expect(formatHeightFromCm(152.4, kWeightUnitLb), "5'0\"");
      expect(formatHeightFromCm(180, kWeightUnitLb), "5'11\"");
    });

    test('carries 12 rounded inches up into the next foot', () {
      // 152.3 cm is 59.96in — rounding the inches must yield 5'0", never 4'12".
      expect(formatHeightFromCm(152.3, kWeightUnitLb), "5'0\"");
    });

    test('formats the bounds themselves without overflowing', () {
      expect(formatHeightFromCm(kMinHeightCm, kWeightUnitLb), "2'7\"");
      expect(formatHeightFromCm(kMaxHeightCm, kWeightUnitLb), "8'2\"");
    });
  });

  group('round-trip through the display boundary', () {
    test('cm survives format -> parse', () {
      final formatted = formatHeightFromCm(165.5, kWeightUnitKg);
      expect(parseHeightToCm(formatted, kWeightUnitKg), closeTo(165.5, 0.001));
    });

    test('feet+inches survives format -> parse', () {
      final formatted = formatHeightFromCm(165.1, kWeightUnitLb);
      expect(parseHeightToCm(formatted, kWeightUnitLb), closeTo(165.1, 0.01));
    });

    test('every whole inch in range formats to something re-parseable', () {
      for (var inches = 32; inches <= 98; inches++) {
        final cm = inchToCm(inches.toDouble());
        final formatted = formatHeightFromCm(cm, kWeightUnitLb);
        expect(parseHeightToCm(formatted, kWeightUnitLb), closeTo(cm, 0.01),
            reason: '$inches in -> $formatted');
      }
    });
  });

  group('the height bounds themselves', () {
    test('are the plausible-human range in canonical cm', () {
      expect(kMinHeightCm, 80.0);
      expect(kMaxHeightCm, 250.0);
    });
  });
}
