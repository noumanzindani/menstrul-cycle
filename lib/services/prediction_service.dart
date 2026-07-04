import 'dart:math';

import '../common/date_utils.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../models/prediction.dart';

/// On-device calendar-method predictions. Pure and deterministic given [asOf],
/// so it is fully unit-testable. NOTHING here is a contraceptive guarantee.
class PredictionService {
  const PredictionService._();

  /// Luteal phase length is relatively constant (~14 days) across people, so
  /// ovulation is estimated by counting back from the next period.
  static const int _lutealDays = 14;

  /// Egg viable ~1 day, sperm ~5 days → fertile window = ovulation −5 … +1.
  static const int _fertilePreOvulation = 5;
  static const int _fertilePostOvulation = 1;

  /// Projects the next [count] periods forward from [anchorStart], stepping by
  /// [cycleLength] days with a [periodLength]-day bleed. Only periods whose end
  /// is today or later are returned (past ones are dropped). Pure/deterministic.
  ///
  /// The fertile window for each period is the one that PRECEDES it: ovulation
  /// ≈ start − 14 (luteal), window = ovulation −5 … +1.
  static List<PredictedPeriod> projectFuturePeriods({
    required DateTime anchorStart,
    required int cycleLength,
    required int periodLength,
    int count = 12,
    DateTime? asOf,
  }) {
    final today = dateOnly(asOf ?? DateTime.now());
    final anchor = dateOnly(anchorStart);
    final safeCycle = cycleLength < 1 ? 28 : cycleLength;
    final safePeriod = periodLength < 1 ? 1 : periodLength;

    final result = <PredictedPeriod>[];
    // Start from the first cycle at/after the anchor and walk forward until we
    // have [count] periods that haven't fully passed.
    var i = 0;
    while (result.length < count && i < count + 400) {
      final start = anchor.add(Duration(days: safeCycle * i));
      i++;
      final end = start.add(Duration(days: safePeriod - 1));
      if (end.isBefore(today)) continue; // drop periods already over
      final ovulation = start.subtract(const Duration(days: _lutealDays));
      result.add(PredictedPeriod(
        start: start,
        end: end,
        ovulation: ovulation,
        fertileStart:
            ovulation.subtract(const Duration(days: _fertilePreOvulation)),
        fertileEnd: ovulation.add(const Duration(days: _fertilePostOvulation)),
      ));
    }
    return result;
  }

  static PredictionResult predict(
    List<Cycle> cycles, {
    int fallbackCycleLength = 28,
    int fallbackPeriodLength = 5,
    DateTime? asOf,
  }) {
    final today = dateOnly(asOf ?? DateTime.now());

    // Cycle lengths come only from COMPLETE cycles (those with a next start).
    final lengths = [
      for (final c in cycles)
        if (c.lengthDays != null) c.lengthDays!,
    ];
    final recent =
        lengths.length > 12 ? lengths.sublist(lengths.length - 12) : lengths;

    final avgCycle =
        recent.isNotEmpty ? _mean(recent).round() : fallbackCycleLength;
    final variability = _stdDev(recent);

    final periodLengths = [for (final c in cycles) c.periodLengthDays];
    final avgPeriod = periodLengths.isNotEmpty
        ? _mean(periodLengths.map((e) => e).toList()).round()
        : fallbackPeriodLength;

    final lastStart = cycles.isNotEmpty ? cycles.last.start : null;

    if (lastStart == null) {
      // No periods logged yet — we can only report defaults.
      return PredictionResult(
        averageCycleLength: avgCycle,
        cycleVariabilityDays: variability,
        averagePeriodLength: avgPeriod,
        cyclesTracked: lengths.length,
        confidence: PredictionConfidence.none,
        lastPeriodStart: null,
        cycleDay: null,
        currentPhase: CyclePhase.unknown,
        nextPeriodStart: null,
        nextPeriodWindowStart: null,
        nextPeriodWindowEnd: null,
        ovulationDay: null,
        fertileWindowStart: null,
        fertileWindowEnd: null,
      );
    }

    final nextStart = lastStart.add(Duration(days: avgCycle));
    final window = max(1, variability.round()); // ± days of uncertainty
    final ovulation = lastStart.add(Duration(days: avgCycle - _lutealDays));
    final fertileStart =
        ovulation.subtract(const Duration(days: _fertilePreOvulation));
    final fertileEnd =
        ovulation.add(const Duration(days: _fertilePostOvulation));

    final cycleDay = daysBetween(lastStart, today) + 1;
    final phase = _phaseFor(
      today: today,
      lastStart: lastStart,
      lastEnd: cycles.last.end,
      avgPeriod: avgPeriod,
      fertileStart: fertileStart,
      fertileEnd: fertileEnd,
    );

    return PredictionResult(
      averageCycleLength: avgCycle,
      cycleVariabilityDays: variability,
      averagePeriodLength: avgPeriod,
      cyclesTracked: lengths.length,
      confidence: _confidenceFor(recent, variability),
      lastPeriodStart: lastStart,
      cycleDay: cycleDay >= 1 ? cycleDay : null,
      currentPhase: phase,
      nextPeriodStart: nextStart,
      nextPeriodWindowStart: nextStart.subtract(Duration(days: window)),
      nextPeriodWindowEnd: nextStart.add(Duration(days: window)),
      ovulationDay: ovulation,
      fertileWindowStart: fertileStart,
      fertileWindowEnd: fertileEnd,
    );
  }

  /// Coarse, confidence-gated fertility level for [today]. Returns a qualitative
  /// [FertilityBand] — NEVER a probability number — because a calendar estimate
  /// can't support precision. Suppressed (`none`) outside the fertile window and
  /// whenever confidence is `none`/`low`, so we never imply a "safe" day.
  static FertilityBand fertilityBand({
    required DateTime today,
    required DateTime? ovulation,
    required DateTime? fertileWindowStart,
    required DateTime? fertileWindowEnd,
    required PredictionConfidence confidence,
  }) {
    if (confidence == PredictionConfidence.none ||
        confidence == PredictionConfidence.low) {
      return FertilityBand.none;
    }
    if (ovulation == null ||
        fertileWindowStart == null ||
        fertileWindowEnd == null) {
      return FertilityBand.none;
    }
    final d = dateOnly(today);
    if (d.isBefore(dateOnly(fertileWindowStart)) ||
        d.isAfter(dateOnly(fertileWindowEnd))) {
      return FertilityBand.none;
    }
    // Days relative to ovulation: negative before, positive after.
    final offset = d.difference(dateOnly(ovulation)).inDays;
    if (offset == 0 || offset == -1) return FertilityBand.peak;
    if (offset == -2 || offset == -3) return FertilityBand.higher;
    return FertilityBand.lower;
  }

  static CyclePhase _phaseFor({
    required DateTime today,
    required DateTime lastStart,
    required DateTime lastEnd,
    required int avgPeriod,
    required DateTime fertileStart,
    required DateTime fertileEnd,
  }) {
    // Menstrual = within the logged period, or the average period length.
    final estMenstrualEnd = lastStart.add(Duration(days: avgPeriod - 1));
    final menstrualEnd = lastEnd.isAfter(estMenstrualEnd) ? lastEnd : estMenstrualEnd;

    if (!today.isBefore(lastStart) && !today.isAfter(menstrualEnd)) {
      return CyclePhase.menstrual;
    }
    if (!today.isBefore(fertileStart) && !today.isAfter(fertileEnd)) {
      return CyclePhase.ovulatory;
    }
    if (today.isBefore(fertileStart)) return CyclePhase.follicular;
    return CyclePhase.luteal;
  }

  /// `high` = plenty of regular cycles; `low` = few or irregular. Thresholds
  /// deliberately conservative so we don't over-promise.
  static PredictionConfidence _confidenceFor(
    List<int> recentLengths,
    double variability,
  ) {
    final n = recentLengths.length;
    if (n == 0) return PredictionConfidence.none;
    final irregular =
        recentLengths.any((l) => l < 21 || l > 35) || variability > 7;
    if (n >= 6 && variability <= 2 && !irregular) {
      return PredictionConfidence.high;
    }
    if (n >= 3 && variability <= 4 && !irregular) {
      return PredictionConfidence.medium;
    }
    return PredictionConfidence.low;
  }

  static double _mean(List<int> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  static double _stdDev(List<int> xs) {
    if (xs.length < 2) return 0;
    final m = _mean(xs);
    final variance =
        xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
            (xs.length - 1);
    return sqrt(variance);
  }
}
