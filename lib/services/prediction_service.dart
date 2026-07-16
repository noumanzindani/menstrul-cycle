import 'dart:math';

import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../models/prediction.dart';
import 'cycle_calculator.dart';
import 'ovulation_signal_service.dart';

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

  /// [capConfidenceToLow] models perimenopause: cycles become erratic, so any
  /// computed confidence is capped at `low`. Because the ovulation marker and
  /// [fertilityBand] are already gated to medium+, this single lever suppresses
  /// every fertility estimate app-wide while leaving the next-period estimate
  /// visible (honestly flagged low). It is a ceiling — `none` stays `none`.
  /// [logs] carries symptothermal signals (OPK results). A positive/peak OPK
  /// near the computed ovulation corroborates the calendar estimate and raises
  /// [PredictionResult.fertilityConfidence] one notch — never [confidence], and
  /// never while [capConfidenceToLow] is set (perimenopause suppression wins).
  /// The whole recompute in one place: raw [logs] + the tracking [mode] → a
  /// [PredictionResult], with the mode-specific health suppressions applied.
  /// Both the foreground (`main.dart`'s ProxyProvider) and the background
  /// isolate (`CheckInWriter`) call this, so the pregnancy/perimenopause rules
  /// can never diverge between them.
  ///
  /// - **Pregnancy**: period/fertility predictions are meaningless and unsafe to
  ///   show, so cycles AND logs are dropped → no prediction.
  /// - **Perimenopause**: cycles are erratic, so confidence is capped to low,
  ///   which self-suppresses the ovulation marker + fertility band app-wide.
  static PredictionResult predictFromLogs({
    required List<DailyLog> logs,
    required TrackingMode mode,
    required int cycleLength,
    required int periodLength,
    DateTime? asOf,
  }) {
    final pregnancy = mode == TrackingMode.pregnancy;
    return predict(
      pregnancy ? const <Cycle>[] : CycleCalculator.computeCycles(logs),
      fallbackCycleLength: cycleLength,
      fallbackPeriodLength: periodLength,
      capConfidenceToLow: mode == TrackingMode.perimenopause,
      asOf: asOf,
      logs: pregnancy ? const <DailyLog>[] : logs,
    );
  }

  static PredictionResult predict(
    List<Cycle> cycles, {
    int fallbackCycleLength = 28,
    int fallbackPeriodLength = 5,
    DateTime? asOf,
    bool capConfidenceToLow = false,
    List<DailyLog> logs = const [],
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
        confidence: _applyCap(PredictionConfidence.none, capConfidenceToLow),
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

    final confidence =
        _applyCap(_confidenceFor(recent, variability), capConfidenceToLow);
    // Symptothermal corroboration: a positive/peak OPK near the estimated
    // ovulation raises ONLY the fertility band's confidence, one notch. Skipped
    // while capping (perimenopause), so the cap stays the ceiling.
    final corroborated = !capConfidenceToLow &&
        OvulationSignalService.opkCorroboratesOvulation(
          logs: logs,
          predictedOvulation: ovulation,
        );
    final fertilityConfidence = OvulationSignalService.raiseFertilityConfidence(
        confidence,
        corroborated: corroborated);

    return PredictionResult(
      averageCycleLength: avgCycle,
      cycleVariabilityDays: variability,
      averagePeriodLength: avgPeriod,
      cyclesTracked: lengths.length,
      confidence: confidence,
      fertilityConfidence: fertilityConfidence,
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

  /// Ceiling helper: clamps [c] to at most `low` when [cap] is set. Never
  /// raises confidence, so a no-data `none` is preserved.
  static PredictionConfidence _applyCap(PredictionConfidence c, bool cap) {
    if (!cap) return c;
    return c.index > PredictionConfidence.low.index
        ? PredictionConfidence.low
        : c;
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
