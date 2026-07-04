import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/cycle_calculator.dart';

/// Builds a minimal DailyLog for a date/flow (other columns don't affect cycles).
DailyLog _log(DateTime date, FlowIntensity? flow) => DailyLog(
      id: 0,
      date: date,
      flow: flow,
      symptoms: '{}',
      createdAt: date,
      updatedAt: date,
    );

void main() {
  group('CycleCalculator.computeCycles', () {
    test('no logs -> no cycles', () {
      expect(CycleCalculator.computeCycles([]), isEmpty);
    });

    test('non-bleeding logs -> no cycles', () {
      final logs = [
        _log(DateTime(2026, 1, 1), FlowIntensity.none),
        _log(DateTime(2026, 1, 2), null),
      ];
      expect(CycleCalculator.computeCycles(logs), isEmpty);
    });

    test('single 5-day period -> one open cycle', () {
      final logs = [
        for (var d = 1; d <= 5; d++)
          _log(DateTime(2026, 1, d), FlowIntensity.medium),
      ];
      final cycles = CycleCalculator.computeCycles(logs);
      expect(cycles, hasLength(1));
      expect(cycles.first.start, DateTime(2026, 1, 1));
      expect(cycles.first.end, DateTime(2026, 1, 5));
      expect(cycles.first.periodLengthDays, 5);
      expect(cycles.first.lengthDays, isNull); // no next cycle yet
    });

    test('two periods 28 days apart -> first cycle length is 28', () {
      final logs = <DailyLog>[
        for (var d = 1; d <= 5; d++)
          _log(DateTime(2026, 1, d), FlowIntensity.medium),
        for (var d = 29; d <= 33; d++)
          _log(DateTime(2026, 1, d), FlowIntensity.medium),
      ];
      final cycles = CycleCalculator.computeCycles(logs);
      expect(cycles, hasLength(2));
      expect(cycles.first.lengthDays, 28);
      expect(cycles.last.lengthDays, isNull);
    });

    test('a single skipped day within a period does not split it', () {
      final logs = [
        _log(DateTime(2026, 3, 1), FlowIntensity.light),
        _log(DateTime(2026, 3, 2), FlowIntensity.heavy),
        // 3rd not logged (gap of 2 days to next)
        _log(DateTime(2026, 3, 4), FlowIntensity.light),
      ];
      final cycles = CycleCalculator.computeCycles(logs);
      expect(cycles, hasLength(1));
      expect(cycles.first.start, DateTime(2026, 3, 1));
      expect(cycles.first.end, DateTime(2026, 3, 4));
    });

    test('a 3-day gap splits into two periods', () {
      final logs = [
        _log(DateTime(2026, 3, 1), FlowIntensity.medium),
        _log(DateTime(2026, 3, 2), FlowIntensity.medium),
        _log(DateTime(2026, 3, 6), FlowIntensity.medium),
      ];
      final cycles = CycleCalculator.computeCycles(logs);
      expect(cycles, hasLength(2));
    });
  });
}
