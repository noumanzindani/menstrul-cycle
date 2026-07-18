import 'enums.dart';

/// A human label paired with how many days it occurred in a cycle.
class LabeledCount {
  const LabeledCount(this.label, this.count);
  final String label;
  final int count;
}

/// Everything logged during one cycle, rolled up per category. A single view of
/// the cycle's experience — bleeding, symptoms, emotions, pain, lifestyle and
/// notes — assembled from the raw day logs inside the cycle's span.
///
/// Medications are intentionally absent: this app has no per-day medication
/// intake log (the Medications table is a schedule, not a diary), so surfacing
/// them here would be inventing data.
class CycleOverview {
  const CycleOverview({
    required this.start,
    required this.periodEnd,
    required this.cycleLength,
    required this.periodLength,
    required this.peakFlow,
    required this.bleedingDays,
    required this.symptoms,
    required this.emotions,
    required this.painAverage,
    required this.painPeak,
    required this.lifestyle,
    required this.notesCount,
  });

  final DateTime start;
  final DateTime periodEnd;
  final int? cycleLength; // null for the still-open current cycle
  final int periodLength;
  final FlowIntensity? peakFlow;
  final int bleedingDays;

  /// Physical symptoms, ranked most-frequent first.
  final List<LabeledCount> symptoms;

  /// Emotional symptoms and moods, ranked most-frequent first.
  final List<LabeledCount> emotions;

  final double? painAverage;
  final int? painPeak;

  /// Lifestyle habits (exercise, caffeine, …), ranked most-frequent first.
  final List<LabeledCount> lifestyle;

  final int notesCount;
}
