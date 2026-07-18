import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../models/flow_analysis.dart';

/// Reduces per-day flow logs into a per-cycle heaviness trend. Pure and
/// deterministic — a function of (cycles, logs) with no DB or clock access, so
/// it is fully unit-testable like [InsightsService].
///
/// Each cycle's heaviness is the mean/peak of the `FlowIntensity` ordinal over
/// the bleeding days that fall inside its [Cycle.start]–[Cycle.end] span. Flow
/// heaviness is self-reported and descriptive; it is never a diagnosis.
class FlowAnalysisService {
  const FlowAnalysisService._();

  static FlowAnalysis analyze(List<Cycle> cycles, List<DailyLog> logs) {
    final series = <FlowTrendPoint>[];
    final tally = <FlowIntensity, int>{};

    for (final c in cycles) {
      final start = dateOnly(c.start);
      final end = dateOnly(c.end);
      final intensities = <FlowIntensity>[];
      for (final l in logs) {
        final f = l.flow;
        if (f == null || f == FlowIntensity.none) continue;
        final d = dateOnly(l.date);
        if (d.isBefore(start) || d.isAfter(end)) continue;
        intensities.add(f);
        tally[f] = (tally[f] ?? 0) + 1;
      }
      if (intensities.isEmpty) continue;

      final sum = intensities.fold<int>(0, (a, f) => a + f.index);
      final peak =
          intensities.reduce((a, b) => a.index >= b.index ? a : b);
      series.add(FlowTrendPoint(
        cycleStart: start,
        avgIntensity: sum / intensities.length,
        peakIntensity: peak,
        bleedingDays: intensities.length,
      ));
    }

    FlowIntensity? typical;
    var best = 0;
    for (final e in tally.entries) {
      if (e.value > best) {
        best = e.value;
        typical = e.key;
      }
    }

    return FlowAnalysis(series: series, typicalFlow: typical);
  }
}
