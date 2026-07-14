import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/month_ring_builder.dart';

/// The month ring paints one segment per day of the CURRENT month, coloured by
/// the day's role. All fertility colouring flows through the confidence-gated
/// PredictionService.fertilityBand, so it can never leak a "safe day". These
/// tests pin the pure day->role mapping (no widget pump).
void main() {
  DailyLog bleeding(DateTime d) => DailyLog(
        id: 0,
        date: d,
        flow: FlowIntensity.medium,
        symptoms: '{}',
        mood: null,
        notes: null,
        bbt: null,
        opk: null,
        createdAt: d,
        updatedAt: d,
      );

  PredictionResult pred({
    required PredictionConfidence fertilityConfidence,
    DateTime? nextPeriodStart,
    DateTime? ovulationDay,
    DateTime? fertileWindowStart,
    DateTime? fertileWindowEnd,
    int averagePeriodLength = 5,
    int? cycleDay = 14,
    CyclePhase phase = CyclePhase.ovulatory,
  }) =>
      PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1,
        averagePeriodLength: averagePeriodLength,
        cyclesTracked: 3,
        confidence: PredictionConfidence.medium,
        lastPeriodStart: DateTime(2026, 7, 2),
        cycleDay: cycleDay,
        currentPhase: phase,
        nextPeriodStart: nextPeriodStart,
        nextPeriodWindowStart: nextPeriodStart?.subtract(const Duration(days: 1)),
        nextPeriodWindowEnd: nextPeriodStart?.add(const Duration(days: 1)),
        ovulationDay: ovulationDay,
        fertileWindowStart: fertileWindowStart,
        fertileWindowEnd: fertileWindowEnd,
        fertilityConfidence: fertilityConfidence,
      );

  RingDayRole roleOn(MonthRingData data, int day) =>
      data.days.firstWhere((d) => d.day == day).role;

  final today = DateTime(2026, 7, 15);
  final logs = [
    bleeding(DateTime(2026, 7, 1)),
    bleeding(DateTime(2026, 7, 2)),
    bleeding(DateTime(2026, 7, 3)),
  ];
  // Fertile window Jul 11..17, ovulation Jul 16; next period Jul 30 (+5 days).
  final p = pred(
    fertilityConfidence: PredictionConfidence.medium,
    nextPeriodStart: DateTime(2026, 7, 30),
    ovulationDay: DateTime(2026, 7, 16),
    fertileWindowStart: DateTime(2026, 7, 11),
    fertileWindowEnd: DateTime(2026, 7, 17),
  );

  test('has exactly one entry per day of the current month', () {
    final d = MonthRingBuilder.build(logs: logs, prediction: p, today: today);
    expect(d.days.length, 31);
    expect(d.year, 2026);
    expect(d.month, 7);
    expect(d.days.map((e) => e.day).toList(),
        List.generate(31, (i) => i + 1));
  });

  test('logged bleeding days are period', () {
    final d = MonthRingBuilder.build(logs: logs, prediction: p, today: today);
    expect(roleOn(d, 1), RingDayRole.period);
    expect(roleOn(d, 3), RingDayRole.period);
  });

  test('the predicted next-period run is coloured predictedPeriod', () {
    final d = MonthRingBuilder.build(logs: logs, prediction: p, today: today);
    expect(roleOn(d, 30), RingDayRole.predictedPeriod);
    expect(roleOn(d, 31), RingDayRole.predictedPeriod);
  });

  test('ovulation day reads as ovulation, surrounding window as fertile', () {
    final d = MonthRingBuilder.build(logs: logs, prediction: p, today: today);
    expect(roleOn(d, 15), RingDayRole.ovulation); // offset -1 -> peak
    expect(roleOn(d, 16), RingDayRole.ovulation); // offset  0 -> peak
    expect(roleOn(d, 14), RingDayRole.fertile); // offset -2 -> higher
    expect(roleOn(d, 13), RingDayRole.fertile); // offset -3 -> higher
    expect(roleOn(d, 11), RingDayRole.fertile); // offset -5 -> lower
    expect(roleOn(d, 17), RingDayRole.fertile); // offset +1 -> lower
  });

  test('days outside every window are normal', () {
    final d = MonthRingBuilder.build(logs: logs, prediction: p, today: today);
    expect(roleOn(d, 20), RingDayRole.normal);
    expect(roleOn(d, 25), RingDayRole.normal);
  });

  test('today is flagged and the centre carries cycle day + phase', () {
    final d = MonthRingBuilder.build(logs: logs, prediction: p, today: today);
    expect(d.days.firstWhere((x) => x.day == 15).isToday, isTrue);
    expect(d.days.where((x) => x.isToday).length, 1);
    expect(d.todayDay, 15);
    expect(d.cycleDay, 14);
    expect(d.phase, CyclePhase.ovulatory);
  });

  test(
      'GUARDRAIL: at low fertility confidence NO day is fertile/ovulation — '
      'even the ovulation day is normal (never a "safe" leak)', () {
    final low = pred(
      fertilityConfidence: PredictionConfidence.low,
      nextPeriodStart: DateTime(2026, 7, 30),
      ovulationDay: DateTime(2026, 7, 16),
      fertileWindowStart: DateTime(2026, 7, 11),
      fertileWindowEnd: DateTime(2026, 7, 17),
    );
    final d = MonthRingBuilder.build(logs: logs, prediction: low, today: today);
    expect(roleOn(d, 15), RingDayRole.normal);
    expect(roleOn(d, 16), RingDayRole.normal);
    expect(roleOn(d, 14), RingDayRole.normal);
    // Period + predicted are NOT fertility-gated, so they still show.
    expect(roleOn(d, 1), RingDayRole.period);
    expect(roleOn(d, 30), RingDayRole.predictedPeriod);
  });

  test('no fertile colouring when the fertility dates are null', () {
    final noFert = pred(
      fertilityConfidence: PredictionConfidence.high,
      nextPeriodStart: DateTime(2026, 7, 30),
      ovulationDay: null,
      fertileWindowStart: null,
      fertileWindowEnd: null,
    );
    final d =
        MonthRingBuilder.build(logs: logs, prediction: noFert, today: today);
    final anyFertility = d.days.any((x) =>
        x.role == RingDayRole.fertile || x.role == RingDayRole.ovulation);
    expect(anyFertility, isFalse);
  });
}
