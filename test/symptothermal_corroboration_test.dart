import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/prediction_service.dart';

/// Wires the symptothermal OPK signal into predictions: a positive/peak
/// ovulation test near the predicted ovulation raises the FERTILITY band's
/// confidence one notch (never the next-period chip), and perimenopause's cap
/// always wins. Corroboration never manufactures a "safe" day.
List<Cycle> _cycles(DateTime firstStart,
    {required int count, int cycleLen = 28, int periodLen = 5}) {
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

DailyLog _opkDay(DateTime date, String opk) => DailyLog(
      id: 0,
      date: date,
      flow: null,
      symptoms: '{}',
      mood: null,
      notes: null,
      bbt: null,
      opk: opk,
      createdAt: date,
      updatedAt: date,
    );

void main() {
  final firstStart = DateTime(2026, 1, 1);

  group('OPK corroboration → fertility confidence', () {
    // 2 cycles → 1 complete → confidence `low`; ovulation = lastStart + 14.
    final cycles = _cycles(firstStart, count: 2);
    final lastStart = cycles.last.start;
    final ovulation = lastStart.add(const Duration(days: 14));

    test('a positive OPK near ovulation raises fertilityConfidence low → medium',
        () {
      final r = PredictionService.predict(
        cycles,
        asOf: lastStart,
        logs: [_opkDay(ovulation, 'positive')],
      );
      // The next-period confidence chip is UNCHANGED — a single test must not
      // overstate cycle-timing precision.
      expect(r.confidence, PredictionConfidence.low);
      // Only the fertility band's confidence steps up.
      expect(r.fertilityConfidence, PredictionConfidence.medium);
    });

    test('no OPK → fertilityConfidence equals the base confidence', () {
      final r = PredictionService.predict(cycles, asOf: lastStart);
      expect(r.fertilityConfidence, r.confidence);
      expect(r.fertilityConfidence, PredictionConfidence.low);
    });

    test('a negative OPK does not raise anything', () {
      final r = PredictionService.predict(
        cycles,
        asOf: lastStart,
        logs: [_opkDay(ovulation, 'negative')],
      );
      expect(r.fertilityConfidence, PredictionConfidence.low);
    });
  });

  group('safety: perimenopause cap beats corroboration', () {
    // 7 cycles → normally `high`; the cap forces `low`.
    final cycles = _cycles(firstStart, count: 7);
    final lastStart = cycles.last.start;
    final ovulation = lastStart.add(const Duration(days: 14));

    test('a positive OPK cannot re-open fertility during perimenopause', () {
      final r = PredictionService.predict(
        cycles,
        asOf: lastStart,
        capConfidenceToLow: true,
        logs: [_opkDay(ovulation, 'positive')],
      );
      expect(r.confidence, PredictionConfidence.low); // capped
      // Corroboration must NOT raise it back to medium — the cap is the ceiling.
      expect(r.fertilityConfidence, PredictionConfidence.low);
    });
  });

  group('safety: corroboration never manufactures a "safe" day', () {
    final cycles = _cycles(firstStart, count: 2);
    final lastStart = cycles.last.start;
    final ovulation = lastStart.add(const Duration(days: 14));

    test('band is unlocked IN the window but stays none OUTSIDE it', () {
      final r = PredictionService.predict(
        cycles,
        asOf: lastStart,
        logs: [_opkDay(ovulation, 'positive')],
      );
      expect(r.fertilityConfidence, PredictionConfidence.medium);

      // Inside the window (ovulation day): the raised confidence unlocks a band.
      final inWindow = PredictionService.fertilityBand(
        today: ovulation,
        ovulation: r.ovulationDay,
        fertileWindowStart: r.fertileWindowStart,
        fertileWindowEnd: r.fertileWindowEnd,
        confidence: r.fertilityConfidence,
      );
      expect(inWindow, isNot(FertilityBand.none));

      // Well after ovulation (luteal): the band self-suppresses — no "safe" read.
      final afterWindow = PredictionService.fertilityBand(
        today: ovulation.add(const Duration(days: 6)),
        ovulation: r.ovulationDay,
        fertileWindowStart: r.fertileWindowStart,
        fertileWindowEnd: r.fertileWindowEnd,
        confidence: r.fertilityConfidence,
      );
      expect(afterWindow, FertilityBand.none);
    });
  });
}
