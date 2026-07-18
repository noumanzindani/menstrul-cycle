import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';

/// The pure decision behind the Home "Did your period start? / Has it ended?"
/// prompts. Given the raw logs + a prediction + today, it returns which single
/// check-in (if any) to surface — and NEVER nags once the day has been answered
/// (a logged flow, bleeding or an explicit "no bleeding", resolves it).
void main() {
  DailyLog log(DateTime date, {FlowIntensity? flow}) => DailyLog(
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

  PredictionResult pred({DateTime? next, int avgPeriod = 5}) => PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1,
        averagePeriodLength: avgPeriod,
        cyclesTracked: 3,
        confidence: PredictionConfidence.high,
        lastPeriodStart: DateTime(2026, 1, 1),
        cycleDay: 1,
        currentPhase: CyclePhase.luteal,
        nextPeriodStart: next,
        nextPeriodWindowStart: next,
        nextPeriodWindowEnd: next,
        ovulationDay: null,
        fertileWindowStart: null,
        fertileWindowEnd: null,
        pmsWindowStart: null,
        pmsWindowEnd: null,
      );

  // A run of bleeding days [start .. start+len-1].
  List<DailyLog> bleeding(DateTime start, int len) => [
        for (var i = 0; i < len; i++)
          log(start.add(Duration(days: i)), flow: FlowIntensity.medium),
      ];

  group('didItStart', () {
    test('asks when the period is due/overdue and today is unlogged', () {
      final result = CycleCheckInService.evaluate(
        logs: const [],
        prediction: pred(next: DateTime(2026, 1, 28)),
        today: DateTime(2026, 1, 28),
      );
      expect(result, CheckInPrompt.didItStart);
    });

    test('does not ask before the next period is due', () {
      final result = CycleCheckInService.evaluate(
        logs: const [],
        prediction: pred(next: DateTime(2026, 2, 1)),
        today: DateTime(2026, 1, 20),
      );
      expect(result, CheckInPrompt.none);
    });

    test('stops once today is marked "no bleeding" (not yet)', () {
      final today = DateTime(2026, 1, 28);
      final result = CycleCheckInService.evaluate(
        logs: [log(today, flow: FlowIntensity.none)],
        prediction: pred(next: today),
        today: today,
      );
      expect(result, CheckInPrompt.none);
    });

    test('stops once today is logged as bleeding (it started)', () {
      final today = DateTime(2026, 1, 28);
      final result = CycleCheckInService.evaluate(
        logs: [log(today, flow: FlowIntensity.medium)],
        prediction: pred(next: today),
        today: today,
      );
      expect(result, CheckInPrompt.none);
    });
  });

  group('hasItEnded', () {
    test('asks when on a period that has run to at least average length', () {
      // Period Jan 1..5 (avg 5); today Jan 6, unlogged.
      final result = CycleCheckInService.evaluate(
        logs: bleeding(DateTime(2026, 1, 1), 5),
        prediction: pred(next: DateTime(2026, 1, 28), avgPeriod: 5),
        today: DateTime(2026, 1, 6),
      );
      expect(result, CheckInPrompt.hasItEnded);
    });

    test('does not ask while the period is still shorter than average', () {
      // Period Jan 1..3 (avg 5); today Jan 4, unlogged — too early.
      final result = CycleCheckInService.evaluate(
        logs: bleeding(DateTime(2026, 1, 1), 3),
        prediction: pred(next: DateTime(2026, 1, 28), avgPeriod: 5),
        today: DateTime(2026, 1, 4),
      );
      expect(result, CheckInPrompt.none);
    });

    test('stops once today is marked "no bleeding" (it ended)', () {
      // Period Jan 1..5 then today Jan 6 marked none.
      final logs = [
        ...bleeding(DateTime(2026, 1, 1), 5),
        log(DateTime(2026, 1, 6), flow: FlowIntensity.none),
      ];
      final result = CycleCheckInService.evaluate(
        logs: logs,
        prediction: pred(next: DateTime(2026, 1, 28), avgPeriod: 5),
        today: DateTime(2026, 1, 6),
      );
      expect(result, CheckInPrompt.none);
    });
  });

  test('no prompt without a prediction and no active period', () {
    final result = CycleCheckInService.evaluate(
      logs: const [],
      prediction: pred(next: null),
      today: DateTime(2026, 1, 15),
    );
    expect(result, CheckInPrompt.none);
  });
}
