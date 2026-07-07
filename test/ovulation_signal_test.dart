import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/ovulation_signal_service.dart';

/// Symptothermal corroboration: a positive/peak ovulation test (OPK) that lands
/// near the predicted ovulation biologically CORROBORATES the calendar estimate,
/// so the fertility band's confidence steps up one notch — unlocking the band
/// exactly when it is actionable. It NEVER lowers confidence and never
/// manufactures a "safe" day (the band still self-suppresses outside the window).
void main() {
  DailyLog day(DateTime date, {String? opk}) => DailyLog(
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

  final ovulation = DateTime(2026, 5, 15);

  group('raiseFertilityConfidence — one notch, never lowers', () {
    test('raises low → medium when corroborated', () {
      expect(
        OvulationSignalService.raiseFertilityConfidence(
            PredictionConfidence.low,
            corroborated: true),
        PredictionConfidence.medium,
      );
    });

    test('raises medium → high when corroborated', () {
      expect(
        OvulationSignalService.raiseFertilityConfidence(
            PredictionConfidence.medium,
            corroborated: true),
        PredictionConfidence.high,
      );
    });

    test('high stays high (no overflow)', () {
      expect(
        OvulationSignalService.raiseFertilityConfidence(
            PredictionConfidence.high,
            corroborated: true),
        PredictionConfidence.high,
      );
    });

    test('none stays none — a stray OPK never manufactures a band from no data',
        () {
      expect(
        OvulationSignalService.raiseFertilityConfidence(
            PredictionConfidence.none,
            corroborated: true),
        PredictionConfidence.none,
      );
    });

    test('not corroborated → unchanged (identity)', () {
      for (final c in PredictionConfidence.values) {
        expect(
          OvulationSignalService.raiseFertilityConfidence(c,
              corroborated: false),
          c,
        );
      }
    });
  });

  group('opkCorroboratesOvulation — leading signal near the window', () {
    test('positive OPK on ovulation day corroborates', () {
      expect(
        OvulationSignalService.opkCorroboratesOvulation(
          logs: [day(ovulation, opk: 'positive')],
          predictedOvulation: ovulation,
        ),
        isTrue,
      );
    });

    test('peak OPK within the ±3-day window corroborates', () {
      expect(
        OvulationSignalService.opkCorroboratesOvulation(
          logs: [day(ovulation.subtract(const Duration(days: 2)), opk: 'peak')],
          predictedOvulation: ovulation,
        ),
        isTrue,
      );
    });

    test('a negative OPK never corroborates', () {
      expect(
        OvulationSignalService.opkCorroboratesOvulation(
          logs: [day(ovulation, opk: 'negative')],
          predictedOvulation: ovulation,
        ),
        isFalse,
      );
    });

    test('a positive OPK far from the prediction does not corroborate', () {
      expect(
        OvulationSignalService.opkCorroboratesOvulation(
          logs: [day(ovulation.subtract(const Duration(days: 9)), opk: 'positive')],
          predictedOvulation: ovulation,
        ),
        isFalse,
      );
    });

    test('null predicted ovulation → no corroboration', () {
      expect(
        OvulationSignalService.opkCorroboratesOvulation(
          logs: [day(ovulation, opk: 'positive')],
          predictedOvulation: null,
        ),
        isFalse,
      );
    });

    test('no OPK logs → no corroboration', () {
      expect(
        OvulationSignalService.opkCorroboratesOvulation(
          logs: [day(ovulation)],
          predictedOvulation: ovulation,
        ),
        isFalse,
      );
    });
  });
}
