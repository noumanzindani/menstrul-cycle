/// How consistent the user's cycle lengths are, from length variability.
/// Thresholds match the narrator's language (≤3.5 d regular, ≤7 d fairly
/// regular, >7 d the red-flag "vary quite a bit" zone). Descriptive, not a
/// diagnosis.
enum CycleRegularity { regular, fairlyRegular, irregular, unknown }

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

  /// A coarse regularity category for a visual indicator. Needs at least three
  /// complete cycles for variability to mean anything; below that it's unknown.
  CycleRegularity get regularity {
    if (cyclesTracked < 3) return CycleRegularity.unknown;
    if (variability > 7) return CycleRegularity.irregular;
    if (variability > 3.5) return CycleRegularity.fairlyRegular;
    return CycleRegularity.regular;
  }
}

/// A gentle, NON-diagnostic notice. Never a diagnosis, never alarmist — always
/// framed as "worth mentioning to a clinician".
class RedFlag {
  const RedFlag(this.title, this.message);
  final String title;
  final String message;
}

/// A NON-diagnostic prompt to discuss a specific pattern (e.g. PCOS, endo,
/// PMDD) with a clinician. [key] identifies the pattern (for tests/analytics);
/// it is never a diagnosis and never a probability/score.
class PatternNudge {
  const PatternNudge(this.key, this.title, this.message);
  final String key; // 'pcos' | 'endo' | 'pmdd'
  final String title;
  final String message;
}

/// A single plain-language "Your patterns" observation about the user's OWN
/// data (e.g. "Your last 3 cycles ran about 2 days shorter than earlier").
/// Descriptive, never diagnostic and never a probability — the clinical prompts
/// live in [RedFlag]/[PatternNudge]. [key] is a stable id for tests/ordering.
class CycleNarrative {
  const CycleNarrative(this.key, this.text);
  final String key; // 'cycle_trend' | 'symptom_phase' | 'regularity' | ...
  final String text;
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
