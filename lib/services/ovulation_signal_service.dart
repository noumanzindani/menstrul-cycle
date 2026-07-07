import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/prediction.dart';

/// Symptothermal corroboration of the calendar-method fertility estimate.
///
/// A positive/peak ovulation test (OPK) is a LEADING biological signal — the LH
/// surge precedes ovulation by ~24–36h — so when one lands near the predicted
/// ovulation it corroborates the calendar and the fertility band's confidence
/// steps up one notch, unlocking the band exactly when it is still actionable.
///
/// Deliberately one-directional: it ONLY raises confidence, never lowers it, and
/// it is applied strictly to the fertility band — never to the next-period
/// estimate — so a single test can't overstate cycle-timing precision. It never
/// manufactures a "safe" reading: the band still self-suppresses outside the
/// window, and perimenopause's confidence cap always wins over this raise.
class OvulationSignalService {
  const OvulationSignalService._();

  /// OPK results that indicate the LH surge (see `kOpkOptions`). A negative test
  /// carries no corroborating information.
  static const Set<String> _surgeResults = {'positive', 'peak'};

  /// How close (in days, either side) a surge must sit to the predicted
  /// ovulation to count as corroboration. Wide enough to absorb the normal
  /// LH-surge-to-ovulation lag, narrow enough that a wildly-off reading in an
  /// irregular cycle does NOT falsely boost confidence.
  static const int _defaultWindowDays = 3;

  /// True when a positive/peak OPK sits within [windowDays] of
  /// [predictedOvulation]. Returns false when there is no prediction to
  /// corroborate, so we never boost confidence out of thin air.
  static bool opkCorroboratesOvulation({
    required List<DailyLog> logs,
    required DateTime? predictedOvulation,
    int windowDays = _defaultWindowDays,
  }) {
    if (predictedOvulation == null) return false;
    final ov = dateOnly(predictedOvulation);
    for (final l in logs) {
      if (!_surgeResults.contains(l.opk)) continue;
      final delta = dateOnly(l.date).difference(ov).inDays.abs();
      if (delta <= windowDays) return true;
    }
    return false;
  }

  /// Steps [base] up exactly one notch when [corroborated]. `none` stays `none`
  /// (no cycle data means no band, regardless of a stray test) and `high` cannot
  /// overflow. Never lowers — the identity when not corroborated.
  static PredictionConfidence raiseFertilityConfidence(
    PredictionConfidence base, {
    required bool corroborated,
  }) {
    if (!corroborated) return base;
    switch (base) {
      case PredictionConfidence.low:
        return PredictionConfidence.medium;
      case PredictionConfidence.medium:
        return PredictionConfidence.high;
      case PredictionConfidence.none:
      case PredictionConfidence.high:
        return base;
    }
  }
}
