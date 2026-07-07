import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/insights_service.dart';

/// PCOS / endo / PMDD awareness nudges. These are NON-diagnostic prompts to
/// discuss a pattern with a clinician — so the tests pin down both when each
/// one appears AND, just as importantly, when it must stay silent (a false
/// "you might have PCOS" is the harm we design against).
void main() {
  DailyLog day(DateTime date,
          {FlowIntensity? flow, String? mood, String symptoms = '{}'}) =>
      DailyLog(
        id: 0,
        date: date,
        flow: flow,
        symptoms: symptoms,
        mood: mood,
        notes: null,
        bbt: null,
        opk: null,
        createdAt: date,
        updatedAt: date,
      );

  Cycle cyc(DateTime start, int? length) =>
      Cycle(start: start, end: start.add(const Duration(days: 3)), lengthDays: length);

  Set<String> keys(List cycles, List logs) => InsightsService.patternNudges(
        cycles: cycles.cast<Cycle>(),
        logs: logs.cast<DailyLog>(),
      ).map((n) => n.key).toSet();

  group('PCOS nudge', () {
    test('fires for persistently long/irregular cycles', () {
      final cycles = [
        cyc(DateTime(2026, 1, 1), 40),
        cyc(DateTime(2026, 2, 10), 42),
        cyc(DateTime(2026, 3, 24), 38),
        cyc(DateTime(2026, 5, 1), 45),
      ];
      expect(keys(cycles, const []), contains('pcos'));
    });

    test('stays silent for regular cycles', () {
      final cycles = [
        cyc(DateTime(2026, 1, 1), 28),
        cyc(DateTime(2026, 1, 29), 29),
        cyc(DateTime(2026, 2, 27), 28),
        cyc(DateTime(2026, 3, 27), 30),
      ];
      expect(keys(cycles, const []), isNot(contains('pcos')));
    });

    test('stays silent on thin data (fewer than 4 cycles)', () {
      final cycles = [cyc(DateTime(2026, 1, 1), 40), cyc(DateTime(2026, 2, 10), 42)];
      expect(keys(cycles, const []), isNot(contains('pcos')));
    });
  });

  group('Endometriosis nudge', () {
    test('fires when severe pain (>=7) is logged on several days', () {
      final logs = [
        day(DateTime(2026, 1, 2), symptoms: encodeDayTags(numbers: {kMetricPain: 8})),
        day(DateTime(2026, 1, 3), symptoms: encodeDayTags(numbers: {kMetricPain: 9})),
        day(DateTime(2026, 2, 1), symptoms: encodeDayTags(numbers: {kMetricPain: 7})),
      ];
      expect(keys(const [], logs), contains('endo'));
    });

    test('stays silent for mild pain or too few days', () {
      final logs = [
        day(DateTime(2026, 1, 2), symptoms: encodeDayTags(numbers: {kMetricPain: 4})),
        day(DateTime(2026, 1, 3), symptoms: encodeDayTags(numbers: {kMetricPain: 8})),
      ];
      expect(keys(const [], logs), isNot(contains('endo')));
    });
  });

  group('PMS/PMDD nudge', () {
    // Two complete cycles of 30 days: next starts are Jan 31 and Mar 2, so the
    // 5-day premenstrual windows are Jan 26–30 and Feb 25–Mar 1.
    final cycles = [
      cyc(DateTime(2026, 1, 1), 30),
      cyc(DateTime(2026, 1, 31), 30),
      cyc(DateTime(2026, 3, 2), null), // most recent, still open
    ];

    test('fires when low mood clusters in the days before the period', () {
      final logs = [
        day(DateTime(2026, 1, 28), mood: 'irritable'),
        day(DateTime(2026, 2, 27), mood: 'sad'),
      ];
      expect(keys(cycles, logs), contains('pmdd'));
    });

    test('stays silent for chronic daily low mood (no cyclical clustering)', () {
      final logs = [
        for (var d = 1; d <= 27; d++)
          day(DateTime(2026, 1, d), mood: 'sad'), // low mood all month, not just pre-period
        day(DateTime(2026, 1, 28), mood: 'sad'),
      ];
      expect(keys(cycles, logs), isNot(contains('pmdd')));
    });
  });

  test('no nudges at all on empty history', () {
    expect(keys(const [], const []), isEmpty);
  });
}
