import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/services/prediction_service.dart';

void main() {
  group('projectFuturePeriods', () {
    final anchor = DateTime(2026, 1, 1);

    test('projects the requested count of periods', () {
      final periods = PredictionService.projectFuturePeriods(
        anchorStart: anchor,
        cycleLength: 28,
        periodLength: 5,
        count: 12,
        asOf: anchor,
      );
      expect(periods, hasLength(12));
    });

    test('periods step by the cycle length', () {
      final periods = PredictionService.projectFuturePeriods(
        anchorStart: anchor,
        cycleLength: 30,
        periodLength: 4,
        count: 3,
        asOf: anchor,
      );
      expect(periods[0].start, DateTime(2026, 1, 1));
      expect(periods[0].end, DateTime(2026, 1, 4)); // 4-day period
      expect(periods[1].start, DateTime(2026, 1, 31)); // +30
      expect(periods[2].start, DateTime(2026, 3, 2)); // +60
      expect(periods[0].lengthDays, 4);
    });

    test('drops periods that already ended before today', () {
      // asOf is two cycles in; the first period is long over.
      final periods = PredictionService.projectFuturePeriods(
        anchorStart: anchor,
        cycleLength: 28,
        periodLength: 5,
        count: 3,
        asOf: DateTime(2026, 2, 15),
      );
      // Every returned period should end on/after asOf.
      for (final p in periods) {
        expect(p.end.isBefore(DateTime(2026, 2, 15)), isFalse);
      }
      expect(periods, hasLength(3));
    });

    test('fertile window precedes the period (28-day → 13..19 days before)', () {
      final periods = PredictionService.projectFuturePeriods(
        anchorStart: anchor,
        cycleLength: 28,
        periodLength: 5,
        count: 2,
        asOf: anchor,
      );
      final second = periods[1]; // starts 2026-01-29
      // ovulation = start - 14 = Jan 15; fertile = Jan 10 .. Jan 16
      expect(second.ovulation, DateTime(2026, 1, 15));
      expect(second.fertileStart, DateTime(2026, 1, 10));
      expect(second.fertileEnd, DateTime(2026, 1, 16));
    });

    test('guards against nonsense cycle length', () {
      final periods = PredictionService.projectFuturePeriods(
        anchorStart: anchor,
        cycleLength: 0,
        periodLength: 0,
        count: 2,
        asOf: anchor,
      );
      expect(periods, hasLength(2)); // falls back to 28/1, no crash
    });
  });
}
