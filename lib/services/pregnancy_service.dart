import '../common/date_utils.dart';

/// Pregnancy dating via Naegele's rule (estimated due date = LMP + 280 days).
/// AWARENESS ONLY — the due date is always labelled an estimate, and the app
/// provides no medical, fetal, or clinical guidance.
class PregnancyService {
  const PregnancyService._();

  static const int _gestationDays = 280; // 40 weeks from the last period

  /// Estimated due date from the last-menstrual-period [lmp] date.
  static DateTime estimatedDueDate(DateTime lmp) =>
      dateOnly(lmp).add(const Duration(days: _gestationDays));

  /// Gestational age today (or [asOf]) as completed weeks + extra days. Never
  /// negative (clamped to 0 before the start date).
  static ({int weeks, int days}) gestationalAge(DateTime lmp, {DateTime? asOf}) {
    final total = daysBetween(dateOnly(lmp), dateOnly(asOf ?? DateTime.now()));
    final clamped = total < 0 ? 0 : total;
    return (weeks: clamped ~/ 7, days: clamped % 7);
  }

  /// Trimester: 1 (weeks < 14), 2 (14–27), 3 (>= 28).
  static int trimester(DateTime lmp, {DateTime? asOf}) {
    final weeks = gestationalAge(lmp, asOf: asOf).weeks;
    if (weeks < 14) return 1;
    if (weeks < 28) return 2;
    return 3;
  }
}
