import 'dart:math';

import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../models/insights.dart';

/// Turns the user's OWN cycle/symptom data into plain-language "Your patterns"
/// observations. Pure and deterministic — no LLM, no network, no dependencies.
///
/// Everything here is DESCRIPTIVE, never diagnostic: it reports what the data
/// does ("your last 3 cycles ran shorter"), never what it means for health. The
/// clinical prompts live in [InsightsService] red-flags/nudges. Each narrative
/// is gated on enough data so a thin log never produces false precision, and the
/// word "safe" never appears. Results are ordered most-notable first, so a
/// caller (Home) can show `first` as the single highlight.
class InsightsNarrator {
  const InsightsNarrator._();

  static const int _minCyclesForRegularity = 3;
  static const int _minCyclesForTrend = 5;
  static const int _recentWindow = 3;
  static const int _lutealDays = 14;
  static const int _minSymptomOccurrences = 3;
  static const double _clusterFraction = 0.6;
  static const int _maxSymptomNarratives = 2;

  static List<CycleNarrative> narrate({
    required List<Cycle> cycles,
    required List<DailyLog> logs,
    int? currentCycleDay,
    CyclePhase? currentPhase,
    DateTime? asOf,
  }) {
    final result = <CycleNarrative>[];
    // Only COMPLETE cycles feed the trends: the open current cycle's period may
    // still be ongoing, which would skew a "periods getting shorter" read.
    final lengths = [
      for (final c in cycles)
        if (c.lengthDays != null) c.lengthDays!,
    ];
    final periodLengths = [
      for (final c in cycles)
        if (c.lengthDays != null) c.periodLengthDays,
    ];

    // Most-notable first, so Home's single highlight leads with a trend or a
    // correlation rather than the always-available "where am I now" phase line.
    final cycleTrend = _trend(lengths, minDelta: 2, subject: 'cycles');
    if (cycleTrend != null) result.add(CycleNarrative('cycle_trend', cycleTrend));

    result.addAll(_symptomPhase(cycles, logs));

    final regularity = _regularity(lengths);
    if (regularity != null) result.add(CycleNarrative('regularity', regularity));

    final periodTrend = _trend(periodLengths, minDelta: 1, subject: 'periods');
    if (periodTrend != null) result.add(CycleNarrative('period_trend', periodTrend));

    final phase = _phase(currentCycleDay, currentPhase);
    if (phase != null) result.add(CycleNarrative('phase', phase));

    return result;
  }

  /// "very regular" / "fairly regular" / "vary a little". Silent above 7 days of
  /// variability — that is the red-flag's territory, and duplicating it would
  /// turn a neutral observation into a second alarm.
  static String? _regularity(List<int> lengths) {
    if (lengths.length < _minCyclesForRegularity) return null;
    final v = _stdDev(lengths);
    if (v > 7) return null;
    if (v <= 1.5) {
      return 'Your cycles have been very regular — within about a day of each other.';
    }
    if (v <= 3.5) {
      return 'Your cycles have been fairly regular from month to month.';
    }
    return 'Your cycles vary a little from month to month, which is common.';
  }

  /// Recent [_recentWindow] values vs the ones before. [subject] is 'cycles' or
  /// 'periods'; [minDelta] is the rounded day change worth mentioning.
  static String? _trend(List<int> xs,
      {required int minDelta, required String subject}) {
    if (xs.length < _minCyclesForTrend) return null;
    final recent = xs.sublist(xs.length - _recentWindow);
    final prior = xs.sublist(0, xs.length - _recentWindow);
    if (prior.isEmpty) return null;
    final delta = (_mean(recent) - _mean(prior)).round();
    if (delta.abs() < minDelta) return null;
    final n = delta.abs();
    final days = n == 1 ? 'day' : 'days';
    final dir = delta < 0 ? 'shorter' : 'longer';
    if (subject == 'periods') {
      return 'Your recent periods have been about $n $days $dir than before.';
    }
    return 'Your last 3 cycles have run about $n $days $dir than the cycles before.';
  }

  static String? _phase(int? day, CyclePhase? phase) {
    if (day == null || phase == null || phase == CyclePhase.unknown) return null;
    final desc = switch (phase) {
      CyclePhase.menstrual => "you're in your period",
      CyclePhase.follicular => 'your follicular phase, leading up to ovulation',
      CyclePhase.ovulatory => 'around your estimated fertile window',
      CyclePhase.luteal => 'your luteal phase, after ovulation',
      CyclePhase.unknown => '',
    };
    return 'Day $day of your cycle — $desc.';
  }

  /// For each frequently-logged symptom, the phase it clusters in (if any). Pure
  /// co-occurrence — "you most often log X around your luteal phase" — never a
  /// causal claim. Capped at [_maxSymptomNarratives] to avoid a wall of text.
  static List<CycleNarrative> _symptomPhase(
      List<Cycle> cycles, List<DailyLog> logs) {
    final tally = <String, Map<CyclePhase, int>>{};
    for (final l in logs) {
      final phase = _phaseOf(dateOnly(l.date), cycles);
      if (phase == null) continue;
      for (final key in decodeSymptoms(l.symptoms)) {
        (tally[key] ??= {})[phase] = ((tally[key]![phase]) ?? 0) + 1;
      }
    }

    final candidates = <({String key, CyclePhase phase, int total})>[];
    tally.forEach((key, byPhase) {
      final total = byPhase.values.fold(0, (a, b) => a + b);
      if (total < _minSymptomOccurrences) return;
      final top = byPhase.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (top.value / total >= _clusterFraction) {
        candidates.add((key: key, phase: top.key, total: total));
      }
    });
    candidates.sort((a, b) => b.total.compareTo(a.total));

    return [
      for (final c in candidates.take(_maxSymptomNarratives))
        CycleNarrative(
          'symptom_phase',
          'You most often log ${symptomLabel(c.key).toLowerCase()} '
              'around your ${_phaseLabel(c.phase)}.',
        ),
    ];
  }

  /// The cycle phase a [date] fell in, using the complete cycle that contains
  /// it. Returns null for dates in the open (current) cycle — its luteal span
  /// isn't defined yet without a next start.
  static CyclePhase? _phaseOf(DateTime date, List<Cycle> cycles) {
    for (final c in cycles) {
      if (c.lengthDays == null) continue;
      final start = dateOnly(c.start);
      final next = start.add(Duration(days: c.lengthDays!));
      if (date.isBefore(start) || !date.isBefore(next)) continue;
      if (!date.isAfter(dateOnly(c.end))) return CyclePhase.menstrual;
      final idx = daysBetween(start, date);
      final ov = c.lengthDays! - _lutealDays;
      if (ov < 0) return CyclePhase.follicular;
      if ((idx - ov).abs() <= 1) return CyclePhase.ovulatory;
      if (idx > ov + 1) return CyclePhase.luteal;
      return CyclePhase.follicular;
    }
    return null;
  }

  static String _phaseLabel(CyclePhase p) => switch (p) {
        CyclePhase.menstrual => 'period',
        CyclePhase.follicular => 'follicular phase',
        CyclePhase.ovulatory => 'fertile window',
        CyclePhase.luteal => 'luteal phase',
        CyclePhase.unknown => 'cycle',
      };

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
