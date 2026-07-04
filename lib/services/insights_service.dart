import 'dart:math';

import '../common/date_utils.dart';
import '../models/cycle.dart';
import '../models/insights.dart';

/// Computes cycle statistics and gentle red-flag notices from cycle history.
/// Pure and deterministic given [asOf] — fully unit-testable.
///
/// Red-flag thresholds follow common clinical reference ranges (ACOG/FIGO):
/// typical cycle 21–35 days, period ≤ 7 days, no period for 90+ days is worth
/// discussing. These are AWARENESS prompts, never diagnoses.
class InsightsService {
  const InsightsService._();

  static Insights analyze(List<Cycle> cycles, {DateTime? asOf}) {
    final today = dateOnly(asOf ?? DateTime.now());

    final lengths = [
      for (final c in cycles)
        if (c.lengthDays != null) c.lengthDays!,
    ];
    final periodLengths = [for (final c in cycles) c.periodLengthDays];

    final stats = CycleStats(
      cyclesTracked: lengths.length,
      averageCycleLength: lengths.isEmpty ? null : _mean(lengths).round(),
      shortestCycle: lengths.isEmpty ? null : lengths.reduce(min),
      longestCycle: lengths.isEmpty ? null : lengths.reduce(max),
      variability: _stdDev(lengths),
      averagePeriodLength:
          periodLengths.isEmpty ? null : _mean(periodLengths).round(),
      longestPeriod: periodLengths.isEmpty ? null : periodLengths.reduce(max),
      daysSinceLastPeriod:
          cycles.isEmpty ? null : daysBetween(cycles.last.start, today),
    );

    return Insights(
      stats: stats,
      flags: _flags(stats, lengths, periodLengths),
      cycleLengthSeries: lengths,
    );
  }

  static List<RedFlag> _flags(
    CycleStats stats,
    List<int> lengths,
    List<int> periodLengths,
  ) {
    final flags = <RedFlag>[];

    // Amenorrhea awareness: no period for a long time.
    if ((stats.daysSinceLastPeriod ?? 0) >= 90) {
      flags.add(const RedFlag(
        'No period logged in a while',
        'It has been 90+ days since your last logged period. If you are not '
            'pregnant, this is worth mentioning to a clinician.',
      ));
    }

    // Cycle-length ranges (need at least 2 cycles so a single outlier from
    // sparse logging doesn\'t raise a false notice).
    if (lengths.length >= 2) {
      if (lengths.any((l) => l < 21)) {
        flags.add(const RedFlag(
          'Some cycles are short',
          'A few of your cycles are shorter than 21 days. If this keeps '
              'happening, consider mentioning it to a clinician.',
        ));
      }
      if (lengths.any((l) => l > 35)) {
        flags.add(const RedFlag(
          'Some cycles are long',
          'A few of your cycles are longer than 35 days. If this is a change '
              'for you, it may be worth discussing with a clinician.',
        ));
      }
    }

    // Irregularity.
    if (lengths.length >= 3 && stats.variability > 7) {
      flags.add(const RedFlag(
        'Your cycles vary quite a bit',
        'Your cycle length varies more than average. Tracking a few more '
            'cycles helps — and it can be worth mentioning to a clinician.',
      ));
    }

    // Long periods.
    if (periodLengths.any((p) => p > 7)) {
      flags.add(const RedFlag(
        'Some periods last over a week',
        'One or more periods lasted more than 7 days. If your periods are '
            'consistently long or heavy, consider talking to a clinician.',
      ));
    }

    return flags;
  }

  static double _mean(List<int> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  static double _stdDev(List<int> xs) {
    if (xs.length < 2) return 0;
    final m = _mean(xs);
    return sqrt(
      xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (xs.length - 1),
    );
  }
}
