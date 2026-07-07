import 'dart:math';

import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
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

  /// NON-diagnostic "worth discussing with a clinician" nudges for patterns
  /// that logged data can hint at (PCOS, endometriosis, PMS/PMDD). Deliberately
  /// conservative — a false alarm is worse than a miss. Never a score/%, never
  /// "you have X".
  static const int _severePain = 7; // on the 0–10 pain scale
  static const int _premenstrualDays = 5;
  static const Set<String> _negativeMoods = {
    'sad', 'anxious', 'irritable', 'angry',
  };
  static const Set<String> _negativeEmotional = {
    'mood_swings', 'anxiety', 'low_mood', 'irritability', 'tearful',
    'low_motivation',
  };

  static List<PatternNudge> patternNudges({
    required List<Cycle> cycles,
    required List<DailyLog> logs,
  }) {
    final nudges = <PatternNudge>[];

    // PCOS: persistently long / irregular cycles (needs a real history so a
    // single long cycle from sparse logging can't trip it).
    final lengths = [
      for (final c in cycles)
        if (c.lengthDays != null) c.lengthDays!,
    ];
    if (lengths.length >= 4) {
      final longCount = lengths.where((l) => l > 35).length;
      if (longCount >= 2 || _stdDev(lengths) >= 9) {
        nudges.add(const PatternNudge(
          'pcos',
          'Your cycles have often been irregular',
          'Several of your recent cycles have been long or varied a lot. '
              'Irregular cycles have many possible causes — one of them is '
              'PCOS. Consider sharing this pattern with a clinician, who can '
              'help you understand it.',
        ));
      }
    }

    // Endometriosis: recurrent severe period pain.
    final severePainDays = logs
        .where((l) => (decodeNumber(l.symptoms, kMetricPain) ?? 0) >= _severePain)
        .length;
    if (severePainDays >= 3) {
      nudges.add(const PatternNudge(
        'endo',
        "You've logged severe pain several times",
        'Period pain this intense is not something you simply have to put up '
            'with. A clinician can help look into the causes, which sometimes '
            'include endometriosis.',
      ));
    }

    // PMS/PMDD: negative mood clustering in the days before the period.
    if (_pmddPattern(cycles, logs)) {
      nudges.add(const PatternNudge(
        'pmdd',
        'Tough moods before your period',
        'Your low mood, irritability, or anxiety has tended to appear in the '
            'days before your period. When these feelings are strong enough to '
            'affect daily life, the pattern is worth discussing with a '
            'clinician — it can relate to PMS or PMDD.',
      ));
    }

    return nudges;
  }

  static bool _isNegativeAffect(DailyLog log) {
    if (log.mood != null && _negativeMoods.contains(log.mood)) return true;
    return decodeSymptoms(log.symptoms).any(_negativeEmotional.contains);
  }

  /// True when negative moods cluster in the premenstrual window across ≥2
  /// cycles AND outnumber the negatives elsewhere — the second clause stops a
  /// chronically low-mood user from being mislabelled as cyclical (PMDD).
  static bool _pmddPattern(List<Cycle> cycles, List<DailyLog> logs) {
    final windows = <({DateTime start, DateTime end})>[];
    for (final c in cycles) {
      if (c.lengthDays == null) continue; // no known next start
      final nextStart = dateOnly(c.start).add(Duration(days: c.lengthDays!));
      windows.add((
        start: nextStart.subtract(const Duration(days: _premenstrualDays)),
        end: nextStart.subtract(const Duration(days: 1)),
      ));
    }
    if (windows.length < 2) return false;

    var premNeg = 0;
    var nonPremNeg = 0;
    final cyclesWithPremNeg = <int>{};
    for (final log in logs) {
      if (!_isNegativeAffect(log)) continue;
      final d = dateOnly(log.date);
      var inWindow = false;
      for (var i = 0; i < windows.length; i++) {
        final w = windows[i];
        if (!d.isBefore(w.start) && !d.isAfter(w.end)) {
          inWindow = true;
          cyclesWithPremNeg.add(i);
        }
      }
      inWindow ? premNeg++ : nonPremNeg++;
    }
    return cyclesWithPremNeg.length >= 2 && premNeg >= 2 && premNeg >= nonPremNeg;
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
