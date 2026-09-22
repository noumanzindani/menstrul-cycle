import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import 'cycle_phase_history.dart';

/// One metric across the four phases. [cells] holds only the phases with
/// enough readings; a missing phase means "not enough data", never zero.
class PhaseProfileRow {
  const PhaseProfileRow(this.label, this.cells);
  final String label;
  final Map<CyclePhase, String> cells;
}

class PhaseProfile {
  const PhaseProfile(this.rows);
  final List<PhaseProfileRow> rows;
}

class PeriodPain {
  const PeriodPain(this.start, this.worst);
  final DateTime start;
  final int worst;
}

class PainSummary {
  const PainSummary({
    required this.periods,
    required this.averageWorst,
    required this.severeDays,
  });

  /// Newest first.
  final List<PeriodPain> periods;
  final double averageWorst;

  /// Days at [CyclePatternsService.severePain] or more in the last 90 days.
  final int severeDays;
}

class EarlyWarning {
  const EarlyWarning({
    required this.key,
    required this.daysBefore,
    required this.seen,
    required this.of,
  });

  final String key;
  final int daysBefore;
  final int seen;
  final int of;

  String get text {
    final days = daysBefore == 1 ? '1 day' : '$daysBefore days';
    return '${dayTagLabel(key)} usually starts about $days before your '
        'period (in $seen of your last $of cycles).';
  }
}

class PeriodShape {
  const PeriodShape({
    required this.heaviestDay,
    required this.typicalLength,
    required this.typicalByDay,
    required this.periods,
  });

  /// 1-based day of the period.
  final int heaviestDay;
  final int typicalLength;
  final List<FlowIntensity> typicalByDay;
  final int periods;

  String get text => 'Across your last $periods periods, flow was usually '
      'heaviest on day $heaviestDay, and periods usually lasted about '
      '$typicalLength days.';
}

class FertilitySigns {
  const FertilitySigns({this.opkDays, this.mucusDays});

  /// 1-based cycle days (first, last) across cycles, or null if too few.
  final (int, int)? opkDays;
  final (int, int)? mucusDays;

  static String _range((int, int) r) =>
      r.$1 == r.$2 ? 'cycle day ${r.$1}' : 'cycle days ${r.$1}–${r.$2}';

  String? get opkText => opkDays == null
      ? null
      : 'Your first positive ovulation test has fallen on '
          '${_range(opkDays!)}.';

  String? get mucusText => mucusDays == null
      ? null
      : 'Egg-white or watery mucus has first appeared on '
          '${_range(mucusDays!)}.';
}

class LifestyleLink {
  const LifestyleLink({
    required this.habit,
    required this.symptom,
    required this.withCount,
    required this.habitDays,
    required this.otherCount,
    required this.otherDays,
  });

  final String habit;
  final String symptom;
  final int withCount;
  final int habitDays;
  final int otherCount;
  final int otherDays;

  String get text => 'You logged ${dayTagLabel(symptom).toLowerCase()} on '
      '$withCount of $habitDays days you logged '
      '${dayTagLabel(habit).toLowerCase()}, and on $otherCount of $otherDays '
      'other days.';
}

class DataCoverage {
  const DataCoverage({
    required this.completeCycles,
    required this.loggedDays,
    required this.since,
  });

  final int completeCycles;
  final int loggedDays;
  final DateTime since;

  String get text {
    final cycles =
        completeCycles == 1 ? '1 complete cycle' : '$completeCycles complete cycles';
    final days = loggedDays == 1 ? '1 logged day' : '$loggedDays logged days';
    return 'Based on $cycles and $days.';
  }
}

/// Descriptive pattern cards for Insights, over the user's own logs.
///
/// Pure and deterministic, like `InsightsNarrator`. Every result is gated on
/// enough data and returns null/empty below it, because a pattern read off two
/// data points is false precision. Nothing here states a cause, a score or a
/// probability, and phase attribution uses COMPLETE cycles only
/// ([phaseOfDate]), so the current cycle is never guessed at.
class CyclePatternsService {
  const CyclePatternsService._();

  static const int minCyclesForProfile = 2;
  static const int minReadingsPerCell = 3;
  static const int severePain = 7;
  static const int _severeWindowDays = 90;
  static const int _warningWindowDays = 7;
  static const int _minWarningCycles = 3;
  static const double _warningFraction = 0.6;
  static const int _maxWarnings = 3;
  static const int _minPeriodsForShape = 3;
  static const int _minCyclesForSigns = 2;
  static const int _minHabitDays = 5;
  static const int _minLinkCount = 3;
  static const double _minLinkGap = 0.25;
  static const int _maxLinks = 3;

  static const List<CyclePhase> phases = [
    CyclePhase.menstrual,
    CyclePhase.follicular,
    CyclePhase.ovulatory,
    CyclePhase.luteal,
  ];

  // ── 1. Phase by phase ────────────────────────────────────────────────────

  static PhaseProfile? phaseProfile(List<Cycle> cycles, List<DailyLog> logs) {
    if (cycles.where((c) => c.isComplete).length < minCyclesForProfile) {
      return null;
    }
    final byPhase = <CyclePhase, List<DailyLog>>{};
    for (final l in logs) {
      final p = phaseOfDate(l.date, cycles);
      if (p != null) (byPhase[p] ??= []).add(l);
    }

    PhaseProfileRow? numeric(String label, String key, String Function(double) fmt) {
      final cells = <CyclePhase, String>{};
      for (final p in phases) {
        final values = [
          for (final l in byPhase[p] ?? const <DailyLog>[])
            if ((decodeNumber(l.symptoms, key) ?? 0) > 0)
              decodeNumber(l.symptoms, key)!.toDouble(),
        ];
        if (values.length < minReadingsPerCell) continue;
        cells[p] = fmt(values.reduce((a, b) => a + b) / values.length);
      }
      return cells.length >= 2 ? PhaseProfileRow(label, cells) : null;
    }

    PhaseProfileRow? categorical(String label, String? Function(DailyLog) read,
        List<TrackOption> options, String Function(String) shorten) {
      final cells = <CyclePhase, String>{};
      for (final p in phases) {
        final counts = <String, int>{};
        for (final l in byPhase[p] ?? const <DailyLog>[]) {
          final v = read(l);
          if (v != null) counts[v] = (counts[v] ?? 0) + 1;
        }
        final total = counts.values.fold(0, (a, b) => a + b);
        if (total < minReadingsPerCell) continue;
        final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
        final option = options.where((o) => o.key == top.key);
        if (option.isEmpty) continue; // unknown keys are dropped, never raw
        cells[p] = shorten(option.first.label);
      }
      return cells.length >= 2 ? PhaseProfileRow(label, cells) : null;
    }

    String outOf5(double v) => v.toStringAsFixed(1);
    final rows = [
      numeric('Energy', kMetricEnergy, outOf5),
      numeric('Stress', kMetricStress, outOf5),
      numeric('Sleep', kMetricSleep, (v) => '${v.toStringAsFixed(1)} h'),
      numeric('Sleep quality', kMetricSleepQuality, outOf5),
      categorical('Mood', (l) => l.mood, kMoodOptions, (s) => s),
      categorical('Libido', (l) => decodeLibido(l.symptoms), kLibidoOptions,
          (s) => s.replaceAll(' libido', '')),
    ].whereType<PhaseProfileRow>().toList();
    return rows.isEmpty ? null : PhaseProfile(rows);
  }

  // ── 2. Pain over time ────────────────────────────────────────────────────

  static PainSummary? painSummary(List<Cycle> cycles, List<DailyLog> logs,
      {required DateTime asOf}) {
    final painByDay = <DateTime, int>{
      for (final l in logs)
        if ((decodeNumber(l.symptoms, kMetricPain) ?? 0) > 0)
          dateOnly(l.date): decodeNumber(l.symptoms, kMetricPain)!.round(),
    };
    final periods = <PeriodPain>[];
    for (final c in cycles.reversed) {
      var worst = 0;
      for (var day = dateOnly(c.start);
          !day.isAfter(dateOnly(c.end));
          day = _addDays(day, 1)) {
        final p = painByDay[day];
        if (p != null && p > worst) worst = p;
      }
      if (worst > 0) periods.add(PeriodPain(dateOnly(c.start), worst));
    }
    if (periods.length < 2) return null;

    final windowStart = _addDays(dateOnly(asOf), -_severeWindowDays);
    final severe = painByDay.entries
        .where((e) =>
            e.value >= severePain &&
            !e.key.isBefore(windowStart) &&
            !e.key.isAfter(dateOnly(asOf)))
        .length;
    final avg = periods.map((p) => p.worst).reduce((a, b) => a + b) /
        periods.length;
    return PainSummary(
      periods: periods.take(6).toList(),
      averageWorst: avg,
      severeDays: severe,
    );
  }

  // ── 3. Early warning ─────────────────────────────────────────────────────

  static List<EarlyWarning> earlyWarnings(
      List<Cycle> cycles, List<DailyLog> logs) {
    final complete = cycles.where((c) => c.isComplete).toList();
    if (complete.length < _minWarningCycles) return const [];
    final tagsByDay = <DateTime, Set<String>>{
      for (final l in logs) dateOnly(l.date): decodeSymptomLikeTags(l.symptoms),
    };

    // key -> "days before" for each cycle whose pre-period window had it.
    final leads = <String, List<int>>{};
    for (final c in complete) {
      final nextStart = _addDays(dateOnly(c.start), c.lengthDays!);
      final firstSeen = <String, int>{};
      for (var k = _warningWindowDays; k >= 1; k--) {
        for (final key in tagsByDay[_addDays(nextStart, -k)] ?? const <String>{}) {
          firstSeen.putIfAbsent(key, () => k);
        }
      }
      firstSeen.forEach((key, k) => (leads[key] ??= []).add(k));
    }

    final out = <EarlyWarning>[];
    leads.forEach((key, ks) {
      if (ks.length < _minWarningCycles) return;
      if (ks.length / complete.length < _warningFraction) return;
      out.add(EarlyWarning(
        key: key,
        daysBefore: _median(ks),
        seen: ks.length,
        of: complete.length,
      ));
    });
    out.sort((a, b) {
      final bySeen = b.seen.compareTo(a.seen);
      return bySeen != 0 ? bySeen : a.key.compareTo(b.key);
    });
    return out.take(_maxWarnings).toList();
  }

  // ── 5. Period, day by day ────────────────────────────────────────────────

  static PeriodShape? periodShape(List<Cycle> cycles, List<DailyLog> logs) {
    final flowByDay = <DateTime, FlowIntensity>{
      for (final l in logs)
        if (l.flow != null && l.flow!.isBleeding) dateOnly(l.date): l.flow!,
    };
    // Complete cycles only: the current period may still be going.
    final periods = [
      for (final c in cycles)
        if (c.isComplete)
          [
            for (var i = 0; i < c.periodLengthDays; i++)
              flowByDay[_addDays(dateOnly(c.start), i)],
          ],
    ];
    if (periods.length < _minPeriodsForShape) return null;
    final recent =
        periods.length > 6 ? periods.sublist(periods.length - 6) : periods;

    final heaviest = <int>[];
    for (final p in recent) {
      var best = -1;
      var bestDay = 0;
      for (var i = 0; i < p.length; i++) {
        final f = p[i];
        if (f != null && f.index > best) {
          best = f.index;
          bestDay = i + 1;
        }
      }
      if (bestDay > 0) heaviest.add(bestDay);
    }
    if (heaviest.length < _minPeriodsForShape) return null;
    final length = _median([for (final p in recent) p.length]);

    final typical = <FlowIntensity>[];
    for (var i = 0; i < length; i++) {
      final counts = <FlowIntensity, int>{};
      for (final p in recent) {
        if (i < p.length && p[i] != null) {
          counts[p[i]!] = (counts[p[i]!] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) break;
      typical.add(counts.entries
          .reduce((a, b) => a.value > b.value ||
                  (a.value == b.value && a.key.index > b.key.index)
              ? a
              : b)
          .key);
    }
    return PeriodShape(
      heaviestDay: _median(heaviest),
      typicalLength: length,
      typicalByDay: typical,
      periods: recent.length,
    );
  }

  // ── 6. Fertility signs (the caller shows this in Conceive mode only) ────

  static FertilitySigns? fertilitySigns(
      List<Cycle> cycles, List<DailyLog> logs) {
    final byDay = {for (final l in logs) dateOnly(l.date): l};
    final opk = <int>[];
    final mucus = <int>[];
    for (final c in cycles.where((c) => c.isComplete)) {
      int? firstOpk;
      int? firstMucus;
      for (var i = 0; i < c.lengthDays!; i++) {
        final l = byDay[_addDays(dateOnly(c.start), i)];
        if (l == null) continue;
        if (firstOpk == null && (l.opk == 'positive' || l.opk == 'peak')) {
          firstOpk = i + 1;
        }
        final cm = decodeSingle(l.symptoms, kDischargeKeyPrefix);
        if (firstMucus == null && (cm == 'cm_eggwhite' || cm == 'cm_watery')) {
          firstMucus = i + 1;
        }
      }
      if (firstOpk != null) opk.add(firstOpk);
      if (firstMucus != null) mucus.add(firstMucus);
    }
    (int, int)? range(List<int> xs) => xs.length < _minCyclesForSigns
        ? null
        : (xs.reduce((a, b) => a < b ? a : b), xs.reduce((a, b) => a > b ? a : b));
    final signs = FertilitySigns(opkDays: range(opk), mucusDays: range(mucus));
    return signs.opkDays == null && signs.mucusDays == null ? null : signs;
  }

  // ── 7. Lifestyle alongside symptoms ──────────────────────────────────────

  static List<LifestyleLink> lifestyleLinks(List<DailyLog> logs) {
    final out = <LifestyleLink>[];
    for (final habit in kHabitOptions.map((o) => o.key)) {
      final withHabit = <DailyLog>[];
      final without = <DailyLog>[];
      for (final l in logs) {
        (decodeGroup(l.symptoms, kHabitKeyPrefix).contains(habit)
                ? withHabit
                : without)
            .add(l);
      }
      if (withHabit.length < _minHabitDays || without.length < _minHabitDays) {
        continue;
      }
      final keys = {
        for (final l in withHabit) ...decodeSymptomLikeTags(l.symptoms),
      };
      for (final key in keys) {
        int count(List<DailyLog> ls) =>
            ls.where((l) => decodeSymptomLikeTags(l.symptoms).contains(key)).length;
        final a = count(withHabit);
        final b = count(without);
        if (a < _minLinkCount) continue;
        if (a / withHabit.length - b / without.length < _minLinkGap) continue;
        out.add(LifestyleLink(
          habit: habit,
          symptom: key,
          withCount: a,
          habitDays: withHabit.length,
          otherCount: b,
          otherDays: without.length,
        ));
      }
    }
    double gap(LifestyleLink l) =>
        l.withCount / l.habitDays - l.otherCount / l.otherDays;
    out.sort((a, b) => gap(b).compareTo(gap(a)));
    return out.take(_maxLinks).toList();
  }

  // ── 8. Data coverage ─────────────────────────────────────────────────────

  static DataCoverage? coverage(List<Cycle> cycles, List<DailyLog> logs) {
    if (logs.isEmpty) return null;
    final days = {for (final l in logs) dateOnly(l.date)};
    final since = days.reduce((a, b) => a.isBefore(b) ? a : b);
    return DataCoverage(
      completeCycles: cycles.where((c) => c.isComplete).length,
      loggedDays: days.length,
      since: since,
    );
  }

  /// Calendar-day arithmetic via the constructor, not `Duration`, so a DST
  /// change can never land a "day" at 23:00 the day before.
  static DateTime _addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  static int _median(List<int> xs) {
    final s = [...xs]..sort();
    return s[s.length ~/ 2];
  }
}
