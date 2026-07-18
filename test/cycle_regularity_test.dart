import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/services/insights_service.dart';

/// A visual regularity category derived from cycle-length variability, aligned
/// with the narrator's language: ≤3.5 d regular, ≤7 d fairly regular, >7 d
/// irregular (the red-flag zone). Needs ≥3 cycles, else unknown.
void main() {
  List<Cycle> cyclesFromLengths(List<int> lengths) {
    var start = DateTime(2026, 1, 1);
    final cycles = <Cycle>[];
    for (final len in lengths) {
      cycles.add(Cycle(
          start: start, end: start.add(const Duration(days: 4)), lengthDays: len));
      start = start.add(Duration(days: len));
    }
    cycles.add(Cycle(start: start, end: start.add(const Duration(days: 4))));
    return cycles;
  }

  CycleRegularity regularityOf(List<int> lengths) =>
      InsightsService.analyze(cyclesFromLengths(lengths)).stats.regularity;

  test('regular when lengths barely vary', () {
    expect(regularityOf([28, 28, 29]), CycleRegularity.regular);
  });

  test('fairly regular for moderate variability (3.5 < v <= 7)', () {
    // 24,28,32 -> stdDev 4.0
    expect(regularityOf([24, 28, 32]), CycleRegularity.fairlyRegular);
  });

  test('irregular when variability exceeds 7 days', () {
    expect(regularityOf([21, 28, 40]), CycleRegularity.irregular);
  });

  test('unknown with fewer than 3 cycles', () {
    expect(regularityOf([28, 28]), CycleRegularity.unknown);
  });
}
