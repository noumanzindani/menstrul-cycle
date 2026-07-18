import '../common/catalog.dart';
import '../db/database.dart';
import '../models/symptom_analysis.dart';

/// Counts how often each symptom appears across the user's day logs and derives
/// pain severity from the 0–10 pain metric. Pure and deterministic — a function
/// of the logs alone, fully unit-testable.
///
/// Only PLAIN symptom keys are counted: [decodeSymptoms] already strips the
/// reserved/namespaced groups (sexual activity, cervical mucus, habits) and the
/// numeric metrics, so this stays consistent with the doctor PDF's symptom list.
class SymptomAnalysisService {
  const SymptomAnalysisService._();

  static SymptomAnalysis analyze(List<DailyLog> logs) {
    final counts = <String, int>{};
    final painValues = <int>[];

    for (final l in logs) {
      for (final key in decodeSymptoms(l.symptoms)) {
        counts[key] = (counts[key] ?? 0) + 1; // once per day
      }
      final pain = decodeNumber(l.symptoms, kMetricPain);
      if (pain != null) painValues.add(pain.round());
    }

    final ranked = [
      for (final e in counts.entries)
        SymptomFrequency(
          key: e.key,
          label: symptomLabel(e.key),
          dayCount: e.value,
        ),
    ]..sort((a, b) {
        final byCount = b.dayCount.compareTo(a.dayCount);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });

    return SymptomAnalysis(
      ranked: ranked,
      painAverage: painValues.isEmpty
          ? null
          : painValues.reduce((a, b) => a + b) / painValues.length,
      painPeak: painValues.isEmpty ? null : painValues.reduce((a, b) => a > b ? a : b),
    );
  }
}
