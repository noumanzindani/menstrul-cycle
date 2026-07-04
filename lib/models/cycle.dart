import '../common/date_utils.dart';

/// A derived menstrual cycle: one period run plus the span until the next one.
/// Cycles are computed from daily flow logs (see [CycleCalculator]); they are
/// never stored, so editing history stays consistent.
class Cycle {
  const Cycle({
    required this.start,
    required this.end,
    this.lengthDays,
  });

  /// First bleeding day of this period.
  final DateTime start;

  /// Last bleeding day of this period.
  final DateTime end;

  /// Days from this [start] to the NEXT cycle's start. Null for the most recent
  /// (still-open) cycle, where the next start isn't known yet.
  final int? lengthDays;

  /// Number of bleeding days in the period itself (inclusive).
  int get periodLengthDays => daysBetween(start, end) + 1;

  bool get isComplete => lengthDays != null;
}
