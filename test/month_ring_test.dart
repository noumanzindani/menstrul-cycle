import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/month_ring_builder.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/month_ring.dart';

/// The MonthRing paints the current month with today's date in the centre. It
/// is a fertility surface, so it must never render the word "safe" or a numeric
/// percentage, and its fertile/ovulation legend must disappear when fertility
/// confidence is too low to colour anything.
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

  PredictionResult pred(PredictionConfidence fertilityConfidence) =>
      PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1,
        averagePeriodLength: 5,
        cyclesTracked: 3,
        confidence: PredictionConfidence.medium,
        lastPeriodStart: DateTime(2026, 7, 2),
        cycleDay: 14,
        currentPhase: CyclePhase.ovulatory,
        nextPeriodStart: DateTime(2026, 7, 30),
        nextPeriodWindowStart: DateTime(2026, 7, 29),
        nextPeriodWindowEnd: DateTime(2026, 7, 31),
        ovulationDay: DateTime(2026, 7, 16),
        fertileWindowStart: DateTime(2026, 7, 11),
        fertileWindowEnd: DateTime(2026, 7, 17),
        fertilityConfidence: fertilityConfidence,
      );

  final today = DateTime(2026, 7, 15);
  final logs = [bleeding(DateTime(2026, 7, 1)), bleeding(DateTime(2026, 7, 2))];

  MonthRingData data(PredictionConfidence fc) =>
      MonthRingBuilder.build(logs: logs, prediction: pred(fc), today: today);

  Future<void> pump(WidgetTester tester, MonthRingData d) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: MonthRing(data: d))),
    ));
    await tester.pumpAndSettle();
  }

  MonthRingPainter painterOf(WidgetTester tester) => tester
      .widget<CustomPaint>(find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is MonthRingPainter))
      .painter as MonthRingPainter;

  testWidgets('renders the ring with today\'s date and phase in the centre',
      (tester) async {
    await pump(tester, data(PredictionConfidence.medium));
    expect(find.byType(MonthRing), findsOneWidget);
    expect(find.text('15'), findsOneWidget); // today's date, centre
    expect(find.textContaining('Day 14'), findsOneWidget);
  });

  testWidgets('never renders "safe" or a percentage (guardrails)',
      (tester) async {
    await pump(tester, data(PredictionConfidence.medium));
    expect(find.textContaining('safe'), findsNothing);
    expect(find.textContaining('Safe'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('painter receives one entry per day incl. fertility at medium',
      (tester) async {
    await pump(tester, data(PredictionConfidence.medium));
    final p = painterOf(tester);
    expect(p.data.days.length, 31);
    expect(p.data.hasFertility, isTrue);
  });

  testWidgets('shows Period + Fertile + Ovulation legend at medium confidence',
      (tester) async {
    await pump(tester, data(PredictionConfidence.medium));
    expect(find.text('Period'), findsOneWidget);
    expect(find.text('Fertile'), findsOneWidget);
    expect(find.textContaining('Ovulation'), findsOneWidget);
  });

  testWidgets(
      'legend shows only the fertility roles actually painted this month '
      '(fertile window straddling the month boundary)', (tester) async {
    // Ovulation is Jul 31; the fertile window is Jul 26..Aug 1, so in AUGUST
    // only Aug 1 (offset +1 -> fertile) is coloured and NO day is ovulation.
    final straddle = PredictionResult(
      averageCycleLength: 28,
      cycleVariabilityDays: 1,
      averagePeriodLength: 5,
      cyclesTracked: 3,
      confidence: PredictionConfidence.medium,
      lastPeriodStart: DateTime(2026, 7, 17),
      cycleDay: 20,
      currentPhase: CyclePhase.luteal,
      nextPeriodStart: DateTime(2026, 8, 14),
      nextPeriodWindowStart: DateTime(2026, 8, 13),
      nextPeriodWindowEnd: DateTime(2026, 8, 15),
      ovulationDay: DateTime(2026, 7, 31),
      fertileWindowStart: DateTime(2026, 7, 26),
      fertileWindowEnd: DateTime(2026, 8, 1),
      fertilityConfidence: PredictionConfidence.medium,
    );
    final d = MonthRingBuilder.build(
        logs: const [], prediction: straddle, today: DateTime(2026, 8, 5));
    expect(d.hasFertile, isTrue);
    expect(d.hasOvulation, isFalse);

    await pump(tester, d);
    expect(find.text('Fertile'), findsOneWidget);
    expect(find.textContaining('Ovulation'), findsNothing);
  });

  testWidgets(
      'GUARDRAIL: at low confidence the ring has no fertility and hides the '
      'fertile/ovulation legend, but still shows Period', (tester) async {
    final d = data(PredictionConfidence.low);
    await pump(tester, d);
    expect(painterOf(tester).data.hasFertility, isFalse);
    expect(find.text('Fertile'), findsNothing);
    expect(find.textContaining('Ovulation'), findsNothing);
    expect(find.text('Period'), findsOneWidget);
  });
}
