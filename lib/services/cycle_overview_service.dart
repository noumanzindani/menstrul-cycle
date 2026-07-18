import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/cycle_overview.dart';
import '../models/enums.dart';

/// Rolls one [Cycle]'s raw day logs into a [CycleOverview]. Pure and
/// deterministic — a function of (cycle, logs) only, scoped to the cycle's span
/// `[start, nextStart)` (the whole cycle, not just the bleeding days).
class CycleOverviewService {
  const CycleOverviewService._();

  static final Set<String> _physicalKeys =
      kSymptomOptions.map((o) => o.key).toSet();
  static final Set<String> _emotionalKeys =
      kEmotionalOptions.map((o) => o.key).toSet();

  static CycleOverview summarize(Cycle cycle, List<DailyLog> logs) {
    final start = dateOnly(cycle.start);
    final periodEnd = dateOnly(cycle.end);
    final nextStart =
        cycle.lengthDays == null ? null : start.add(Duration(days: cycle.lengthDays!));

    bool inCycle(DateTime raw) {
      final d = dateOnly(raw);
      return !d.isBefore(start) && (nextStart == null || d.isBefore(nextStart));
    }

    final physical = <String, int>{};
    final emotional = <String, int>{};
    final lifestyle = <String, int>{};
    final painValues = <int>[];
    var notesCount = 0;
    var bleedingDays = 0;
    FlowIntensity? peakFlow;

    for (final l in logs) {
      if (!inCycle(l.date)) continue;
      final d = dateOnly(l.date);

      // Bleeding is counted only within the period run itself.
      final f = l.flow;
      if (f != null && f != FlowIntensity.none && !d.isAfter(periodEnd)) {
        bleedingDays++;
        if (peakFlow == null || f.index > peakFlow.index) peakFlow = f;
      }

      for (final key in decodeSymptoms(l.symptoms)) {
        if (_physicalKeys.contains(key)) {
          physical[key] = (physical[key] ?? 0) + 1;
        } else if (_emotionalKeys.contains(key)) {
          emotional[key] = (emotional[key] ?? 0) + 1;
        }
      }

      final mood = l.mood;
      if (mood != null && mood.isNotEmpty) {
        emotional[mood] = (emotional[mood] ?? 0) + 1;
      }

      for (final key in decodeGroup(l.symptoms, kHabitKeyPrefix)) {
        lifestyle[key] = (lifestyle[key] ?? 0) + 1;
      }

      final pain = decodeNumber(l.symptoms, kMetricPain);
      if (pain != null) painValues.add(pain.round());

      if ((l.notes ?? '').trim().isNotEmpty) notesCount++;
    }

    return CycleOverview(
      start: start,
      periodEnd: periodEnd,
      cycleLength: cycle.lengthDays,
      periodLength: cycle.periodLengthDays,
      peakFlow: peakFlow,
      bleedingDays: bleedingDays,
      symptoms: _rank(physical, (k) => symptomLabel(k)),
      emotions: _rank(emotional, _emotionOrMoodLabel),
      painAverage: painValues.isEmpty
          ? null
          : painValues.reduce((a, b) => a + b) / painValues.length,
      painPeak:
          painValues.isEmpty ? null : painValues.reduce((a, b) => a > b ? a : b),
      lifestyle: _rank(lifestyle, (k) => _labelFrom(kHabitOptions, k)),
      notesCount: notesCount,
    );
  }

  /// Emotional-symptom label, falling back to a mood label (moods and emotional
  /// symptoms share the same tally).
  static String _emotionOrMoodLabel(String key) {
    for (final o in [...kEmotionalOptions, ...kMoodOptions]) {
      if (o.key == key) return o.label;
    }
    return key;
  }

  static String _labelFrom(List<TrackOption> opts, String key) {
    for (final o in opts) {
      if (o.key == key) return o.label;
    }
    return key;
  }

  static List<LabeledCount> _rank(
    Map<String, int> counts,
    String Function(String key) label,
  ) {
    final list = [
      for (final e in counts.entries) LabeledCount(label(e.key), e.value),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });
    return list;
  }
}
