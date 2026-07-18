import 'enums.dart';

/// One cycle's flow summary for the trend chart. [avgIntensity] and
/// [peakIntensity] come from the `FlowIntensity` ordinal (spotting 1 … flooding
/// 5) over the bleeding days inside the cycle's span.
class FlowTrendPoint {
  const FlowTrendPoint({
    required this.cycleStart,
    required this.avgIntensity,
    required this.peakIntensity,
    required this.bleedingDays,
  });

  final DateTime cycleStart;
  final double avgIntensity; // mean of FlowIntensity.index over bleeding days
  final FlowIntensity peakIntensity;
  final int bleedingDays;
}

/// Heavy-vs-light flow trends over the user's cycle history. Descriptive only —
/// bleeding heaviness is self-reported and never a diagnosis.
class FlowAnalysis {
  const FlowAnalysis({required this.series, required this.typicalFlow});

  /// One point per cycle that has flow data, oldest → newest.
  final List<FlowTrendPoint> series;

  /// The most frequently logged bleeding intensity across all cycles, or null
  /// when there's no flow data.
  final FlowIntensity? typicalFlow;

  /// A single point isn't a trend — the chart needs at least two.
  bool get hasData => series.length >= 2;
}
