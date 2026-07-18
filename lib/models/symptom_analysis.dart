/// How often one symptom was logged, in days.
class SymptomFrequency {
  const SymptomFrequency({
    required this.key,
    required this.label,
    required this.dayCount,
  });

  final String key;
  final String label;
  final int dayCount; // number of distinct days this symptom was logged
}

/// Per-symptom frequency plus pain severity over the user's logs. Descriptive
/// only — a count of what the user logged, never a diagnosis.
class SymptomAnalysis {
  const SymptomAnalysis({
    required this.ranked,
    required this.painAverage,
    required this.painPeak,
  });

  /// Symptoms ranked by [SymptomFrequency.dayCount], most-logged first.
  final List<SymptomFrequency> ranked;

  /// Average / peak of the 0–10 pain metric across days that recorded it, or
  /// null when pain was never logged.
  final double? painAverage;
  final int? painPeak;

  bool get hasData => ranked.isNotEmpty;
}
