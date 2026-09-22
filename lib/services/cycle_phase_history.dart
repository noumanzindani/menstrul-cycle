import '../common/date_utils.dart';
import '../models/cycle.dart';
import '../models/enums.dart';

/// Assumed luteal length when placing a past date in a phase. Calendar-only,
/// like every other phase in the app.
const int kHistoryLutealDays = 14;

/// The phase a past [date] fell in, from the COMPLETE cycle containing it.
///
/// Null for any date in the open (current) cycle, whose luteal span is not
/// defined without a next start, and for dates outside every cycle. Shared by
/// `InsightsNarrator` and `CyclePatternsService` so two Insights cards can
/// never place the same day in different phases.
CyclePhase? phaseOfDate(DateTime date, List<Cycle> cycles) {
  final day = dateOnly(date);
  for (final c in cycles) {
    if (c.lengthDays == null) continue;
    final start = dateOnly(c.start);
    final next = start.add(Duration(days: c.lengthDays!));
    if (day.isBefore(start) || !day.isBefore(next)) continue;
    if (!day.isAfter(dateOnly(c.end))) return CyclePhase.menstrual;
    final idx = daysBetween(start, day);
    final ov = c.lengthDays! - kHistoryLutealDays;
    if (ov < 0) return CyclePhase.follicular;
    if ((idx - ov).abs() <= 1) return CyclePhase.ovulatory;
    if (idx > ov + 1) return CyclePhase.luteal;
    return CyclePhase.follicular;
  }
  return null;
}
