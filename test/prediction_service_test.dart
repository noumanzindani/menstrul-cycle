import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/prediction_service.dart';

/// Builds [count] cycles starting at [firstStart], each [cycleLen] apart with a
/// [periodLen]-day period. The last cycle is left open (lengthDays == null).
List<Cycle> _regularCycles(
  DateTime firstStart, {
  required int count,
  int cycleLen = 28,
  int periodLen = 5,
}) {
  final cycles = <Cycle>[];
  var start = firstStart;
  for (var i = 0; i < count; i++) {
    cycles.add(Cycle(
      start: start,
      end: start.add(Duration(days: periodLen - 1)),
      lengthDays: i == count - 1 ? null : cycleLen,
    ));
    start = start.add(Duration(days: cycleLen));
  }
  return cycles;
}

void main() {
  final firstStart = DateTime(2026, 1, 1);

  test('no cycles -> no prediction, confidence none', () {
    final r = PredictionService.predict([]);
    expect(r.hasPrediction, isFalse);
    expect(r.confidence, PredictionConfidence.none);
  });

  group('regular 28-day history', () {
    // 7 periods => 6 complete cycles of length 28.
    final cycles = _regularCycles(firstStart, count: 7);
    final lastStart = cycles.last.start;

    test('averages and high confidence', () {
      final r = PredictionService.predict(cycles, asOf: lastStart);
      expect(r.averageCycleLength, 28);
      expect(r.averagePeriodLength, 5);
      expect(r.cyclesTracked, 6);
      expect(r.confidence, PredictionConfidence.high);
    });

    test('next period is last start + 28 days', () {
      final r = PredictionService.predict(cycles, asOf: lastStart);
      expect(r.nextPeriodStart, lastStart.add(const Duration(days: 28)));
    });

    test('fertile window is ovulation -5..+1 (day 9..15)', () {
      final r = PredictionService.predict(cycles, asOf: lastStart);
      expect(r.ovulationDay, lastStart.add(const Duration(days: 14)));
      expect(r.fertileWindowStart, lastStart.add(const Duration(days: 9)));
      expect(r.fertileWindowEnd, lastStart.add(const Duration(days: 15)));
    });

    test('phase depends on the day within the cycle', () {
      CyclePhase phaseOn(int dayOffset) => PredictionService.predict(
            cycles,
            asOf: lastStart.add(Duration(days: dayOffset)),
          ).currentPhase;

      expect(phaseOn(2), CyclePhase.menstrual); // within period
      expect(phaseOn(7), CyclePhase.follicular); // after period, before fertile
      expect(phaseOn(12), CyclePhase.ovulatory); // inside fertile window
      expect(phaseOn(20), CyclePhase.luteal); // after ovulation
    });
  });

  test('irregular history -> low confidence', () {
    // Lengths 24, 40, 22 => out of 21..35 range and high variability.
    final cycles = <Cycle>[
      Cycle(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 5),
          lengthDays: 24),
      Cycle(
          start: DateTime(2026, 1, 25),
          end: DateTime(2026, 1, 29),
          lengthDays: 40),
      Cycle(
          start: DateTime(2026, 3, 6),
          end: DateTime(2026, 3, 10),
          lengthDays: 22),
      Cycle(
          start: DateTime(2026, 3, 28),
          end: DateTime(2026, 4, 1),
          lengthDays: null),
    ];
    final r = PredictionService.predict(cycles, asOf: DateTime(2026, 3, 28));
    expect(r.confidence, PredictionConfidence.low);
    expect(r.hasPrediction, isTrue);
  });
}
