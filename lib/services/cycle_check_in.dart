import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/prediction.dart';
import 'cycle_calculator.dart';

/// Which "check-in" the Home dashboard should surface right now, if any.
enum CheckInPrompt {
  /// No question to ask today.
  none,

  /// The period is due/overdue but hasn't been logged — "Did it start?".
  didItStart,

  /// A period is underway and has run to at least the typical length —
  /// "Are you still on your period?".
  hasItEnded,
}

/// Decides, from the raw logs + a prediction + today, whether to prompt the user
/// to confirm that their period has started or ended. Pure and deterministic.
///
/// The whole design rests on one fact: "didn't start" and "ended" are the SAME
/// underlying event — a confirmed no-bleeding day (`flow == none`). So a single
/// logged flow of ANY kind (bleeding OR none) answers the day's question and
/// silences the prompt until tomorrow. We never store a separate "answered"
/// flag; the log itself is the answer.
class CycleCheckInService {
  const CycleCheckInService._();

  /// Same one-missed-day tolerance the cycle math uses, so an unlogged gap of a
  /// day doesn't look like the period has ended.
  static const int _gapTolerance = 1;

  static CheckInPrompt evaluate({
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required DateTime today,
  }) {
    final day = dateOnly(today);

    // Already answered today (bleeding or an explicit "no bleeding") → silent.
    if (_logFor(logs, day)?.flow != null) return CheckInPrompt.none;

    // Is a period underway? Take the most recent derived run and see whether
    // today sits within it or just after its last bleeding day (gap tolerance).
    final cycles =
        CycleCalculator.computeCycles(logs, gapToleranceDays: _gapTolerance);
    if (cycles.isNotEmpty) {
      final last = cycles.last;
      final onPeriod = !day.isBefore(last.start) &&
          daysBetween(last.end, day) <= _gapTolerance + 1;
      if (onPeriod) {
        // Only ask once it's run to at least the typical length — otherwise a
        // 2-day-old period would immediately nag "has it ended?".
        return last.periodLengthDays >= prediction.averagePeriodLength
            ? CheckInPrompt.hasItEnded
            : CheckInPrompt.none;
      }
    }

    // Not bleeding now: is the next period due or overdue?
    final next = prediction.nextPeriodStart;
    if (next != null && !day.isBefore(dateOnly(next))) {
      return CheckInPrompt.didItStart;
    }
    return CheckInPrompt.none;
  }

  static DailyLog? _logFor(List<DailyLog> logs, DateTime day) {
    for (final l in logs) {
      if (isSameDay(l.date, day)) return l;
    }
    return null;
  }
}
