import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/flow_analysis_service.dart';

/// Per-cycle flow-intensity trend (heavy vs light over time). Pure function of
/// (cycles, logs): each cycle's in-span bleeding days are mapped to the
/// FlowIntensity ordinal and reduced to an average + peak, oldest -> newest.
void main() {
  DailyLog log(DateTime date, FlowIntensity? flow) => DailyLog(
        id: 0,
        date: date,
        flow: flow,
        symptoms: '{}',
        mood: null,
        notes: null,
        bbt: null,
        opk: null,
        createdAt: date,
        updatedAt: date,
      );

  test('one FlowTrendPoint per cycle with data, oldest -> newest', () {
    final cycles = [
      Cycle(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 3), lengthDays: 28),
      Cycle(start: DateTime(2026, 1, 29), end: DateTime(2026, 1, 31)),
    ];
    final logs = [
      log(DateTime(2026, 1, 1), FlowIntensity.light),
      log(DateTime(2026, 1, 2), FlowIntensity.light),
      log(DateTime(2026, 1, 3), FlowIntensity.medium),
      log(DateTime(2026, 1, 29), FlowIntensity.heavy),
      log(DateTime(2026, 1, 30), FlowIntensity.heavy),
      log(DateTime(2026, 1, 31), FlowIntensity.flooding),
    ];

    final a = FlowAnalysisService.analyze(cycles, logs);

    expect(a.series.length, 2);
    expect(a.series.first.cycleStart, DateTime(2026, 1, 1));
    expect(a.series.first.bleedingDays, 3);
    // light=2, light=2, medium=3 -> mean 2.333…
    expect(a.series.first.avgIntensity, closeTo(2.33, 0.01));
    expect(a.series.first.peakIntensity, FlowIntensity.medium);
    expect(a.series.last.peakIntensity, FlowIntensity.flooding);
    expect(a.series.last.avgIntensity,
        greaterThan(a.series.first.avgIntensity));
    expect(a.hasData, isTrue);
  });

  test('typicalFlow is the most-logged bleeding intensity', () {
    final cycles = [Cycle(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 3))];
    final logs = [
      log(DateTime(2026, 1, 1), FlowIntensity.light),
      log(DateTime(2026, 1, 2), FlowIntensity.light),
      log(DateTime(2026, 1, 3), FlowIntensity.heavy),
    ];

    expect(FlowAnalysisService.analyze(cycles, logs).typicalFlow,
        FlowIntensity.light);
  });

  test('ignores non-bleeding and out-of-span logs; hasData needs >= 2 points',
      () {
    final cycles = [Cycle(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 2))];
    final logs = [
      log(DateTime(2026, 1, 1), FlowIntensity.medium),
      log(DateTime(2026, 1, 2), FlowIntensity.none), // "period ended" marker
      log(DateTime(2026, 1, 15), FlowIntensity.heavy), // outside every span
    ];

    final a = FlowAnalysisService.analyze(cycles, logs);
    expect(a.series.length, 1);
    expect(a.series.first.bleedingDays, 1); // only the medium day counts
    expect(a.hasData, isFalse); // a single point is not a trend
  });
}
