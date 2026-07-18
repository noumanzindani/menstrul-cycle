import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/month_ring.dart';
import '../models/prediction.dart';
import 'prediction_service.dart';

/// Builds the [MonthRingData] for the current month from the user's logs and the
/// current [PredictionResult]. Pure and on-device — no Flutter, no I/O — so the
/// day->role mapping is unit-testable without a widget pump.
///
/// Precedence per day: a logged bleeding day is always [RingDayRole.period];
/// otherwise a day inside the predicted next-period run is
/// [RingDayRole.predictedPeriod]; otherwise fertility colouring is derived
/// SOLELY from [PredictionService.fertilityBand] (which is confidence-gated and
/// window-bounded), so the ring can never show fertility below medium
/// confidence, outside the window, or on missing data — i.e. it can never imply
/// a "safe" day; otherwise a day inside the PMS window is [RingDayRole.pms] —
/// period-timing like [RingDayRole.predictedPeriod], so it is gated only by
/// having a prediction, never by confidence.
class MonthRingBuilder {
  const MonthRingBuilder._();

  static MonthRingData build({
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required DateTime today,
  }) {
    final t = dateOnly(today);
    final year = t.year;
    final month = t.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // Logged bleeding days in this month, indexed by day-of-month for O(1) lookup.
    final bleedingDays = <int>{};
    for (final log in logs) {
      final d = dateOnly(log.date);
      if (d.year == year &&
          d.month == month &&
          (log.flow?.isBleeding ?? false)) {
        bleedingDays.add(d.day);
      }
    }

    final predStart = prediction.nextPeriodStart == null
        ? null
        : dateOnly(prediction.nextPeriodStart!);
    final predLength = prediction.averagePeriodLength;

    final days = [
      for (var dom = 1; dom <= daysInMonth; dom++)
        RingDay(
          day: dom,
          role: _roleFor(
            date: DateTime(year, month, dom),
            dom: dom,
            bleedingDays: bleedingDays,
            predStart: predStart,
            predLength: predLength,
            prediction: prediction,
          ),
          isToday: dom == t.day,
        ),
    ];

    return MonthRingData(
      year: year,
      month: month,
      days: days,
      todayDay: t.day,
      cycleDay: prediction.cycleDay,
      phase: prediction.currentPhase,
    );
  }

  static RingDayRole _roleFor({
    required DateTime date,
    required int dom,
    required Set<int> bleedingDays,
    required DateTime? predStart,
    required int predLength,
    required PredictionResult prediction,
  }) {
    // 1. Logged bleeding always wins (never overpainted by a prediction).
    if (bleedingDays.contains(dom)) return RingDayRole.period;

    // 2. The upcoming predicted period run (gated only by having a prediction —
    // like the next-period card, this is not a fertility/"safe" claim).
    if (predStart != null) {
      final offset = daysBetween(predStart, date);
      if (offset >= 0 && offset < predLength) {
        return RingDayRole.predictedPeriod;
      }
    }

    // 3. Fertility — ONLY through the confidence-gated, window-bounded band.
    // Returns none below medium confidence, outside the window, or on null data.
    final band = PredictionService.fertilityBand(
      today: date,
      ovulation: prediction.ovulationDay,
      fertileWindowStart: prediction.fertileWindowStart,
      fertileWindowEnd: prediction.fertileWindowEnd,
      confidence: prediction.fertilityConfidence,
    );
    switch (band) {
      case FertilityBand.peak:
        return RingDayRole.ovulation;
      case FertilityBand.higher:
      case FertilityBand.lower:
        return RingDayRole.fertile;
      case FertilityBand.none:
        break;
    }

    // 4. PMS window — period-timing (like predictedPeriod above), not a
    // fertility signal, so it is gated only by having a prediction, never by
    // confidence.
    final pmsStart = prediction.pmsWindowStart;
    final pmsEnd = prediction.pmsWindowEnd;
    if (pmsStart != null && pmsEnd != null) {
      final d = dateOnly(date);
      if (!d.isBefore(dateOnly(pmsStart)) && !d.isAfter(dateOnly(pmsEnd))) {
        return RingDayRole.pms;
      }
    }
    return RingDayRole.normal;
  }
}
