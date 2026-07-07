import '../common/date_utils.dart';
import '../db/database.dart';

/// Symptothermal helpers. AWARENESS ONLY — the thermal shift is a rough
/// observation for conceive-mode users. It never feeds the guarded fertility
/// band and never implies contraceptive reliability (a real symptothermal
/// method needs clinical validation, à la Natural Cycles/FDA).
class BbtService {
  const BbtService._();

  static const int _baselineDays = 6;
  static const int _sustainedDays = 3;
  static const double _shiftThreshold = 0.2; // °C above the baseline mean

  /// The date of the first sustained temperature rise (a "thermal shift"), or
  /// null if none is clearly present. Simplified 3-over-6 rule over the
  /// chronologically-ordered BBT readings; deliberately conservative.
  static DateTime? thermalShift(List<DailyLog> logs) {
    final readings = [
      for (final l in logs)
        if (l.bbt != null) (date: dateOnly(l.date), bbt: l.bbt!),
    ]..sort((a, b) => a.date.compareTo(b.date));

    if (readings.length < _baselineDays + _sustainedDays) return null;

    for (var i = _baselineDays; i <= readings.length - _sustainedDays; i++) {
      final baseline = readings
              .sublist(i - _baselineDays, i)
              .map((r) => r.bbt)
              .reduce((a, b) => a + b) /
          _baselineDays;
      final elevated = List.generate(_sustainedDays, (k) => readings[i + k])
          .every((r) => r.bbt >= baseline + _shiftThreshold);
      if (elevated) return readings[i].date;
    }
    return null;
  }
}
