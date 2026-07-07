import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/home_widget_service.dart';

/// The home-screen widget shows one glanceable line. This tests the PURE builder
/// that turns a prediction into that text — the native push is device-only.
void main() {
  final today = DateTime(2026, 6, 1);

  PredictionResult pred({DateTime? next, DateTime? windowEnd}) => PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1,
        averagePeriodLength: 5,
        cyclesTracked: 6,
        confidence: PredictionConfidence.high,
        lastPeriodStart: DateTime(2026, 1, 1),
        cycleDay: 5,
        currentPhase: CyclePhase.follicular,
        nextPeriodStart: next,
        nextPeriodWindowStart: next,
        nextPeriodWindowEnd: windowEnd ?? next,
        ovulationDay: null,
        fertileWindowStart: null,
        fertileWindowEnd: null,
      );

  HomeWidgetData build(PredictionResult p,
          {TrackingMode mode = TrackingMode.track, DateTime? pregStart}) =>
      buildHomeWidgetData(
        prediction: p,
        mode: mode,
        pregnancyStartDate: pregStart,
        now: today,
      );

  test('counts down whole days to the next period', () {
    final d = build(pred(
        next: today.add(const Duration(days: 5)),
        windowEnd: today.add(const Duration(days: 7))));
    expect(d.value, '5');
    expect(d.caption, contains('period'));
  });

  test('singular day when the period is tomorrow', () {
    final d = build(pred(next: today.add(const Duration(days: 1))));
    expect(d.value, '1');
    expect(d.caption, 'day to your period');
  });

  test('says Today on the expected start day', () {
    final d = build(pred(next: today));
    expect(d.value, 'Today');
  });

  test('says Late once the whole window has passed', () {
    final d = build(pred(
        next: today.subtract(const Duration(days: 3)),
        windowEnd: today.subtract(const Duration(days: 1))));
    expect(d.value, 'Late');
  });

  test('empty state prompts logging when there is no prediction', () {
    final d = build(pred(next: null));
    expect(d.value, '—');
    expect(d.caption.toLowerCase(), contains('log'));
  });

  test('pregnancy mode shows gestational week, never a period countdown', () {
    // 12 weeks along; period predictions are suppressed in pregnancy.
    final d = build(
      pred(next: null),
      mode: TrackingMode.pregnancy,
      pregStart: today.subtract(const Duration(days: 7 * 12)),
    );
    expect(d.value, 'Week 12');
    expect(d.caption.toLowerCase(), isNot(contains('period')));
  });
}
