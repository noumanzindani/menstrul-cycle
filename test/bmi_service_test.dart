import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/services/bmi_service.dart';

/// BMI is the ONE place in this app where a body-judgement label is permitted.
/// The ruling in CLAUDE.md ("deliberately no BMI, no height, and no
/// classification of any kind") was reversed by the owner on 2026-09-13 for
/// this module only; `weight_trend_service_test.dart` keeps the reversal
/// contained to this single file.
void main() {
  test('BMI bounds stay in step with the catalog bounds', () {
    // bmi_service.dart restates these by VALUE rather than importing them, to
    // stay a pure service with no Flutter dependency. Nothing in the compiler
    // notices when one side moves, and two agents writing this feature in
    // parallel already picked different height minimums (90 vs 80) before one
    // of them noticed. So the agreement is pinned here rather than asked for in
    // a doc comment.
    //
    // If you are here because this failed: the bounds diverged. Decide which is
    // right and change BOTH, or import catalog.dart into bmi_service.dart and
    // delete its local copies.
    expect(kBmiMinHeightCm, kMinHeightCm, reason: 'min height diverged');
    expect(kBmiMaxHeightCm, kMaxHeightCm, reason: 'max height diverged');
    expect(kBmiMinWeightKg, kMinWeightKg, reason: 'min weight diverged');
    expect(kBmiMaxWeightKg, kMaxWeightKg, reason: 'max weight diverged');
  });

  group('bmiFrom — refusal, never a guess', () {
    test('returns null when height is missing', () {
      expect(BmiService.bmiFrom(weightKg: 70), isNull);
    });

    test('returns null when weight is missing', () {
      expect(BmiService.bmiFrom(heightCm: 170), isNull);
    });

    test('returns null when both are missing', () {
      expect(BmiService.bmiFrom(), isNull);
    });

    test('returns null for an implausible height', () {
      expect(BmiService.bmiFrom(heightCm: 30, weightKg: 70), isNull);
      expect(BmiService.bmiFrom(heightCm: 300, weightKg: 70), isNull);
      expect(BmiService.bmiFrom(heightCm: 0, weightKg: 70), isNull);
      expect(BmiService.bmiFrom(heightCm: -170, weightKg: 70), isNull);
    });

    test('returns null for an implausible weight', () {
      expect(BmiService.bmiFrom(heightCm: 170, weightKg: 10), isNull);
      expect(BmiService.bmiFrom(heightCm: 170, weightKg: 400), isNull);
      expect(BmiService.bmiFrom(heightCm: 170, weightKg: 0), isNull);
    });

    test('accepts the inclusive plausibility bounds themselves', () {
      expect(BmiService.bmiFrom(heightCm: kBmiMinHeightCm, weightKg: 70),
          isNotNull);
      expect(BmiService.bmiFrom(heightCm: kBmiMaxHeightCm, weightKg: 70),
          isNotNull);
      expect(BmiService.bmiFrom(heightCm: 170, weightKg: kBmiMinWeightKg),
          isNotNull);
      expect(BmiService.bmiFrom(heightCm: 170, weightKg: kBmiMaxWeightKg),
          isNotNull);
    });

    test('returns null for NaN and infinity', () {
      // A range check alone does NOT catch NaN: every comparison against NaN is
      // false, so `cm < min || cm > max` waves it through and the formula then
      // yields NaN. This is the regression guard for that.
      expect(BmiService.bmiFrom(heightCm: double.nan, weightKg: 70), isNull);
      expect(BmiService.bmiFrom(heightCm: 170, weightKg: double.nan), isNull);
      expect(BmiService.bmiFrom(heightCm: double.infinity, weightKg: 70),
          isNull);
      expect(
          BmiService.bmiFrom(heightCm: 170, weightKg: double.negativeInfinity),
          isNull);
    });
  });

  group('bmiFrom — the arithmetic', () {
    test('computes kg / m^2', () {
      // 81 / 1.8^2 = 25.0 exactly.
      expect(BmiService.bmiFrom(heightCm: 180, weightKg: 81), closeTo(25.0, 1e-9));
      // 70 / 1.7^2 = 24.2214...
      expect(
        BmiService.bmiFrom(heightCm: 170, weightKg: 70),
        closeTo(24.221453287197235, 1e-9),
      );
    });

    test('does NOT round — rounding belongs at the display edge', () {
      final bmi = BmiService.bmiFrom(heightCm: 170, weightKg: 70)!;
      expect(bmi, isNot(24.2));
      expect(bmi.toStringAsFixed(5), '24.22145');
    });
  });

  group('bmiLabelFor — WHO adult bands', () {
    test('classifies at and around every boundary', () {
      expect(BmiService.bmiLabelFor(15.0), kBmiLabelUnderweight);
      expect(BmiService.bmiLabelFor(18.4), kBmiLabelUnderweight);
      expect(BmiService.bmiLabelFor(18.5), kBmiLabelNormalRange);
      expect(BmiService.bmiLabelFor(24.9), kBmiLabelNormalRange);
      expect(BmiService.bmiLabelFor(25.0), kBmiLabelOverweight);
      expect(BmiService.bmiLabelFor(29.9), kBmiLabelOverweight);
      expect(BmiService.bmiLabelFor(30.0), kBmiLabelObese);
      expect(BmiService.bmiLabelFor(45.0), kBmiLabelObese);
    });

    test('returns null for a missing or non-finite value', () {
      expect(BmiService.bmiLabelFor(null), isNull);
      expect(BmiService.bmiLabelFor(double.nan), isNull);
      expect(BmiService.bmiLabelFor(double.infinity), isNull);
      expect(BmiService.bmiLabelFor(0), isNull);
      expect(BmiService.bmiLabelFor(-3), isNull);
    });

    test('every band label is distinct and non-empty', () {
      const labels = [
        kBmiLabelUnderweight,
        kBmiLabelNormalRange,
        kBmiLabelOverweight,
        kBmiLabelObese,
      ];
      expect(labels.toSet(), hasLength(labels.length));
      expect(labels.any((l) => l.trim().isEmpty), isFalse);
    });
  });

  group('bmiReadout — the only place this copy is assembled', () {
    test('renders the owner-approved shape', () {
      expect(
        BmiService.bmiReadout(heightCm: 170, weightKg: 70),
        'BMI 24.2 - normal range',
      );
    });

    test('returns null whenever the number would be a guess', () {
      expect(BmiService.bmiReadout(heightCm: 170), isNull);
      expect(BmiService.bmiReadout(weightKg: 70), isNull);
      expect(BmiService.bmiReadout(heightCm: 300, weightKg: 70), isNull);
    });

    test('classifies the number it actually SHOWS, not the raw one', () {
      // Raw BMI 24.96 rounds to "25.0" for display. Labelling the raw value
      // would print "BMI 25.0 - normal range", which reads as a bug.
      final raw = BmiService.bmiFrom(heightCm: 170, weightKg: 72.1344)!;
      expect(raw, lessThan(25.0));
      expect(
        BmiService.bmiReadout(heightCm: 170, weightKg: 72.1344),
        'BMI 25.0 - overweight',
      );
    });
  });
}
