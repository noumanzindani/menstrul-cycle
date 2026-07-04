/// Aggregate statistics over a user's cycle history.
class CycleStats {
  const CycleStats({
    required this.cyclesTracked,
    required this.averageCycleLength,
    required this.shortestCycle,
    required this.longestCycle,
    required this.variability,
    required this.averagePeriodLength,
    required this.longestPeriod,
    required this.daysSinceLastPeriod,
  });

  final int cyclesTracked; // complete cycles (with a known length)
  final int? averageCycleLength;
  final int? shortestCycle;
  final int? longestCycle;
  final double variability;
  final int? averagePeriodLength;
  final int? longestPeriod;
  final int? daysSinceLastPeriod;

  bool get hasData => cyclesTracked > 0;
}

/// A gentle, NON-diagnostic notice. Never a diagnosis, never alarmist — always
/// framed as "worth mentioning to a clinician".
class RedFlag {
  const RedFlag(this.title, this.message);
  final String title;
  final String message;
}

/// Everything the Insights screen and PDF report need.
class Insights {
  const Insights({
    required this.stats,
    required this.flags,
    required this.cycleLengthSeries,
  });

  final CycleStats stats;
  final List<RedFlag> flags;

  /// Ordered cycle lengths (oldest → newest) for the trend chart.
  final List<int> cycleLengthSeries;
}
