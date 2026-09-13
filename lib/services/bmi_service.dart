/// BMI: the ONE module in `lib/` allowed to carry body-judgement copy.
///
/// CLAUDE.md's standing ruling is "deliberately no BMI, no height, and no
/// classification of any kind", and `test/weight_trend_service_test.dart`
/// enforces it by scanning every Dart string literal under `lib/`. The project
/// owner **deliberately reversed that ruling on 2026-09-13**, for this feature
/// and this file only: a height field is collected, and Insights shows a BMI
/// readout with a band label.
///
/// The reversal is CONTAINED, not repealed. This file is the sole exemption in
/// that scan, which is why every user-facing word of the readout — the "BMI"
/// prefix included — is assembled HERE and read out by the UI. A caller that
/// writes its own `'BMI '` string is a guardrail failure, not a style nit.
///
/// Pure by construction: no Flutter import, no package import, no `dart:`
/// import. That is also why the plausibility bounds below are declared locally
/// instead of imported — `common/catalog.dart` imports `flutter/material.dart`.
///
/// Scope: this reads `AppSettings.heightCm` and `AppSettings.profileWeightKg`
/// (the profile fields). It has nothing to do with `kMetricWeight`, the per-day
/// metric that drives `WeightTrendService`; those two are separate on purpose.
library;

/// Plausible-human bounds for the BMI inputs, in canonical units.
///
/// Deliberately generous: an out-of-range value is a REFUSAL (null), and
/// refusing a real short or tall user would be a defect, so the bounds only
/// have to exclude fat-fingered entries (a stray decimal point, cm typed as m).
///
/// All four mirror `catalog.dart`'s `kMinHeightCm`/`kMaxHeightCm`/
/// `kMinWeightKg`/`kMaxWeightKg` BY VALUE. They are restated rather than
/// imported to keep this file dependency-free, so keep the two sets in step:
/// a bound wider here than at the input boundary is dead code, and a bound
/// NARROWER here silently drops the readout for a value settings accepted and
/// saved, which reads as the feature being broken.
const double kBmiMinHeightCm = 80.0;
const double kBmiMaxHeightCm = 250.0;
const double kBmiMinWeightKg = 20.0;
const double kBmiMaxWeightKg = 350.0;

/// WHO adult band boundaries, in BMI units. Lower-inclusive: a value is in the
/// band whose threshold it reaches but whose successor it does not.
const double kBmiNormalRangeFloor = 18.5;
const double kBmiOverweightFloor = 25.0;
const double kBmiObeseFloor = 30.0;

/// The band labels. These four strings, plus [BmiService.bmiReadout]'s prefix,
/// are the entire body-judgement vocabulary this app is permitted to ship.
const String kBmiLabelUnderweight = 'underweight';
const String kBmiLabelNormalRange = 'normal range';
const String kBmiLabelOverweight = 'overweight';
const String kBmiLabelObese = 'obese';

/// Body mass index over the stored profile fields. Pure, synchronous, no deps.
class BmiService {
  const BmiService._();

  /// BMI as kg / m², or null when either input is absent or implausible.
  ///
  /// Never rounds — the caller rounds at the display edge (and [bmiReadout]
  /// does exactly that). Never substitutes a default for a missing field: an
  /// unanswered height is not a height.
  static double? bmiFrom({double? heightCm, double? weightKg}) {
    if (heightCm == null || weightKg == null) return null;
    if (!_inRange(heightCm, kBmiMinHeightCm, kBmiMaxHeightCm)) return null;
    if (!_inRange(weightKg, kBmiMinWeightKg, kBmiMaxWeightKg)) return null;
    final metres = heightCm / 100.0;
    return weightKg / (metres * metres);
  }

  /// The WHO adult band for [bmi], or null when [bmi] is absent or not a
  /// positive finite number.
  ///
  /// Classifies EXACTLY the value handed to it. A caller that displays a
  /// rounded number must classify that same rounded number, or the readout can
  /// print a figure that contradicts its own label.
  static String? bmiLabelFor(double? bmi) {
    if (bmi == null || !bmi.isFinite || bmi <= 0) return null;
    if (bmi < kBmiNormalRangeFloor) return kBmiLabelUnderweight;
    if (bmi < kBmiOverweightFloor) return kBmiLabelNormalRange;
    if (bmi < kBmiObeseFloor) return kBmiLabelOverweight;
    return kBmiLabelObese;
  }

  /// The complete user-facing readout, e.g. `BMI 24.2 - normal range`, or null
  /// when there is nothing honest to show.
  ///
  /// The display edge: one decimal place, and the band is taken from the
  /// ROUNDED figure so the number and the label can never disagree.
  static String? bmiReadout({double? heightCm, double? weightKg}) {
    final raw = bmiFrom(heightCm: heightCm, weightKg: weightKg);
    if (raw == null) return null;
    final shown = raw.toStringAsFixed(1);
    final label = bmiLabelFor(double.parse(shown));
    if (label == null) return null;
    return 'BMI $shown - $label';
  }

  static bool _inRange(double v, double min, double max) =>
      v.isFinite && v >= min && v <= max;
}
