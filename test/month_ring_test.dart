import 'dart:ui' as ui;

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
        pmsWindowStart: DateTime(2026, 7, 25),
        pmsWindowEnd: DateTime(2026, 7, 29),
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
    // The centre reads date / cycle day / phase, in that order: the ring is
    // indexed by DAY OF MONTH, "Day 14" is the CYCLE day, and the label line is
    // what keeps those two numbers from being read as one.
    expect(find.text('July 15'), findsOneWidget); // today's date, centre
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
      pmsWindowStart: DateTime(2026, 8, 9),
      pmsWindowEnd: DateTime(2026, 8, 13),
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

  testWidgets('shows a PMS legend entry when a PMS day is painted this month',
      (tester) async {
    await pump(tester, data(PredictionConfidence.medium));
    expect(find.textContaining('PMS'), findsOneWidget);
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

  // ---- reveal animation --------------------------------------------------
  //
  // The ring sweeps in clockwise on first mount, then today's dotted marker
  // fades in over the tail of the timeline. The reveal maths is asserted against
  // a recording Canvas rather than a golden: what matters is WHICH arcs are
  // drawn and how far, not how they rasterise.

  const todayDotColor = Color(0xFFAA0000);
  const haloColor = Color(0xFF00BB00);

  MonthRingPainter painterFor(
    MonthRingData d, {
    required double ring,
    required double dots,
  }) =>
      MonthRingPainter(
        data: d,
        ringReveal: AlwaysStoppedAnimation<double>(ring),
        dotFade: AlwaysStoppedAnimation<double>(dots),
        normal: const Color(0xFF101010),
        period: const Color(0xFF202020),
        predicted: const Color(0xFF303030),
        fertile: const Color(0xFF404040),
        ovulation: const Color(0xFF505050),
        pms: const Color(0xFF606060),
        todayDot: todayDotColor,
        halo: haloColor,
      );

  _RecordingCanvas record(MonthRingPainter p) {
    final canvas = _RecordingCanvas();
    p.paint(canvas, const Size(240, 240));
    return canvas;
  }

  // Arcs are identified by hue, not by exact colour, because the marker's alpha
  // is what the fade drives. The tolerance is not cosmetic: [Paint] stores its
  // colour in a Float32List, so a colour read back off the Paint has been
  // round-tripped through single precision and 2/3 comes back as
  // 0.6666666865348816. Exact == against a double-precision Color never matches.
  bool sameHue(Color a, Color b) =>
      (a.r - b.r).abs() < 1e-6 &&
      (a.g - b.g).abs() < 1e-6 &&
      (a.b - b.b).abs() < 1e-6;

  test('paints nothing at the start of the reveal', () {
    final c =
        record(painterFor(data(PredictionConfidence.medium), ring: 0, dots: 0));
    expect(c.arcs, isEmpty);
  });

  test('reveals the month progressively, drawing the leading day partially',
      () {
    final c = record(
        painterFor(data(PredictionConfidence.medium), ring: 0.5, dots: 0));
    // July has 31 days, so half the ring is 15.5 days: 15 whole arcs plus one
    // drawn at half sweep. Stepping whole segments instead would tie the motion
    // to the frame rate.
    expect(c.arcs.length, 16);
    expect(c.arcs.last.sweepAngle, closeTo(c.arcs.first.sweepAngle * 0.5, 1e-6));
  });

  test('paints every day of the month once the reveal completes', () {
    final c =
        record(painterFor(data(PredictionConfidence.medium), ring: 1, dots: 0));
    expect(c.arcs.length, 31);
    expect(c.arcs.every((a) => a.sweepAngle == c.arcs.first.sweepAngle), isTrue);
  });

  test("withholds today's marker until the ring is complete", () {
    final c = record(
        painterFor(data(PredictionConfidence.medium), ring: 0.9, dots: 0));
    expect(c.arcs.where((a) => sameHue(a.color, todayDotColor)), isEmpty);
    expect(c.arcs.where((a) => sameHue(a.color, haloColor)), isEmpty);
  });

  test("paints today's three dots over a cleared segment when the fade ends",
      () {
    final c =
        record(painterFor(data(PredictionConfidence.medium), ring: 1, dots: 1));
    // ignore: avoid_print
    expect(c.arcs.where((a) => sameHue(a.color, haloColor)).length, 1);
    final dots =
        c.arcs.where((a) => sameHue(a.color, todayDotColor)).toList();
    expect(dots.length, 3);
    expect(dots.every((d) => d.color.a == 1.0), isTrue);
  });

  test("fades today's marker in rather than popping it", () {
    final c = record(
        painterFor(data(PredictionConfidence.medium), ring: 1, dots: 0.5));
    final dots =
        c.arcs.where((a) => sameHue(a.color, todayDotColor)).toList();
    expect(dots.length, 3);
    expect(dots.first.color.a, closeTo(0.5, 1e-6));
    // The halo clear fades with the dots; at full opacity from the first frame
    // of the fade it would punch a hard notch in the finished ring.
    final halo = c.arcs.firstWhere((a) => sameHue(a.color, haloColor));
    expect(halo.color.a, closeTo(0.5, 1e-6));
  });

  testWidgets('animates the ring in rather than snapping to complete',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
          body: Center(child: MonthRing(data: data(PredictionConfidence.medium)))),
    ));
    await tester.pump();
    expect(painterOf(tester).ringReveal.value, 0.0);

    await tester.pump(const Duration(milliseconds: 210));
    final mid = painterOf(tester).ringReveal.value;
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(painterOf(tester).ringReveal.value, 1.0);
    expect(painterOf(tester).dotFade.value, 1.0);
  });

  testWidgets('paints the completed ring on frame one when motion is reduced',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
            body: Center(
                child: MonthRing(data: data(PredictionConfidence.medium)))),
      ),
    ));
    await tester.pump();
    expect(painterOf(tester).ringReveal.value, 1.0);
    expect(painterOf(tester).dotFade.value, 1.0);
  });

  testWidgets('does not replay the reveal when new data arrives',
      (tester) async {
    await pump(tester, data(PredictionConfidence.medium));
    expect(painterOf(tester).ringReveal.value, 1.0);

    // The home screen rebuilds this widget whenever a log is saved; re-sweeping
    // the whole ring on every refresh would be jarring.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
          body: Center(child: MonthRing(data: data(PredictionConfidence.low)))),
    ));
    await tester.pump();
    expect(painterOf(tester).ringReveal.value, 1.0);
  });
}

/// One recorded `drawArc`. The painter reuses a single [Paint] across every arc,
/// so the colour must be copied at record time rather than read back later.
class _RecordedArc {
  const _RecordedArc(this.startAngle, this.sweepAngle, this.color);

  final double startAngle;
  final double sweepAngle;
  final Color color;
}

/// A [Canvas] that records arcs instead of rasterising them, so the reveal maths
/// can be asserted directly without golden files.
class _RecordingCanvas implements ui.Canvas {
  final List<_RecordedArc> arcs = <_RecordedArc>[];

  @override
  void drawArc(ui.Rect rect, double startAngle, double sweepAngle,
      bool useCenter, ui.Paint paint) {
    arcs.add(_RecordedArc(startAngle, sweepAngle, paint.color));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
