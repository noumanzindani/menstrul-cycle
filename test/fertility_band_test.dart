import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/prediction_service.dart';

void main() {
  // Ovulation Jan 15; fertile window Jan 10..16 (ovulation −5..+1).
  final ov = DateTime(2026, 1, 15);
  final wStart = DateTime(2026, 1, 10);
  final wEnd = DateTime(2026, 1, 16);

  FertilityBand band(DateTime today, PredictionConfidence c) =>
      PredictionService.fertilityBand(
        today: today,
        ovulation: ov,
        fertileWindowStart: wStart,
        fertileWindowEnd: wEnd,
        confidence: c,
      );

  group('fertilityBand (qualitative, confidence-gated — never a number)', () {
    test('peaks on ovulation day and the day before', () {
      expect(band(DateTime(2026, 1, 15), PredictionConfidence.high),
          FertilityBand.peak);
      expect(band(DateTime(2026, 1, 14), PredictionConfidence.high),
          FertilityBand.peak);
    });

    test('higher a couple of days before ovulation', () {
      expect(band(DateTime(2026, 1, 13), PredictionConfidence.high),
          FertilityBand.higher);
      expect(band(DateTime(2026, 1, 12), PredictionConfidence.high),
          FertilityBand.higher);
    });

    test('lower at the window edges', () {
      expect(band(DateTime(2026, 1, 10), PredictionConfidence.high),
          FertilityBand.lower);
      expect(band(DateTime(2026, 1, 16), PredictionConfidence.high),
          FertilityBand.lower);
    });

    test('none outside the fertile window', () {
      expect(band(DateTime(2026, 1, 9), PredictionConfidence.high),
          FertilityBand.none);
      expect(band(DateTime(2026, 1, 20), PredictionConfidence.high),
          FertilityBand.none);
    });

    test('suppressed at low/none confidence even on ovulation day', () {
      expect(band(DateTime(2026, 1, 15), PredictionConfidence.low),
          FertilityBand.none);
      expect(band(DateTime(2026, 1, 15), PredictionConfidence.none),
          FertilityBand.none);
    });
  });
}
