import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';

/// Turns raw daily flow logs into structured [Cycle]s.
///
/// Rule: a "period" is a run of bleeding days (flow != none). Two bleeding days
/// belong to the same period if the gap between them is within
/// [gapToleranceDays] blank days (default 1) — this absorbs a single missed log
/// or a one-day pause without splitting one period into two.
class CycleCalculator {
  const CycleCalculator._();

  static List<Cycle> computeCycles(
    List<DailyLog> logs, {
    int gapToleranceDays = 1,
  }) {
    // Collect distinct bleeding days, sorted ascending.
    final bleeding = <DateTime>[];
    for (final log in logs) {
      final flow = log.flow;
      if (flow != null && flow.isBleeding) {
        bleeding.add(dateOnly(log.date));
      }
    }
    bleeding.sort();

    final distinct = <DateTime>[];
    for (final d in bleeding) {
      if (distinct.isEmpty || !isSameDay(distinct.last, d)) distinct.add(d);
    }
    if (distinct.isEmpty) return const [];

    // Split the sorted days into runs wherever the gap exceeds tolerance.
    // Consecutive days differ by 1; one missed day is a gap of 2, etc.
    final runs = <List<DateTime>>[];
    var current = <DateTime>[distinct.first];
    for (var i = 1; i < distinct.length; i++) {
      final gap = daysBetween(distinct[i - 1], distinct[i]);
      if (gap <= gapToleranceDays + 1) {
        current.add(distinct[i]);
      } else {
        runs.add(current);
        current = [distinct[i]];
      }
    }
    runs.add(current);

    // Build cycles; length = start-to-next-start (null for the last run).
    final cycles = <Cycle>[];
    for (var i = 0; i < runs.length; i++) {
      final start = runs[i].first;
      final end = runs[i].last;
      final length =
          i < runs.length - 1 ? daysBetween(start, runs[i + 1].first) : null;
      cycles.add(Cycle(start: start, end: end, lengthDays: length));
    }
    return cycles;
  }
}

extension _FlowBleeding on FlowIntensity {
  bool get isBleeding => this != FlowIntensity.none;
}
