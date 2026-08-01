import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';

/// One logged weight, in canonical kilograms.
class WeightPoint {
  const WeightPoint({required this.date, required this.kg});
  final DateTime date;
  final double kg;
}

/// A chronological weight series plus its net change. DESCRIPTIVE ONLY — there
/// is deliberately no BMI, no target, and no classification of any kind.
class WeightTrend {
  const WeightTrend({required this.points, required this.netChangeKg});
  final List<WeightPoint> points;

  /// Last minus first, in kg. Negative means a decrease.
  final double netChangeKg;
}

class WeightTrendService {
  const WeightTrendService._();

  /// Weight readings within [windowDays] before [asOf], oldest first, or null
  /// when there are fewer than two (a single dot is not a trend).
  static WeightTrend? compute(
    List<DailyLog> logs, {
    required DateTime asOf,
    int windowDays = 90,
  }) {
    final cutoff = dateOnly(asOf).subtract(Duration(days: windowDays));
    final points = <WeightPoint>[];
    for (final l in logs) {
      final kg = decodeNumber(l.symptoms, kMetricWeight)?.toDouble();
      if (kg == null || kg <= 0) continue;
      final date = dateOnly(l.date);
      if (date.isBefore(cutoff)) continue;
      points.add(WeightPoint(date: date, kg: kg));
    }
    if (points.length < 2) return null;
    points.sort((a, b) => a.date.compareTo(b.date));
    return WeightTrend(
      points: points,
      netChangeKg: points.last.kg - points.first.kg,
    );
  }
}
