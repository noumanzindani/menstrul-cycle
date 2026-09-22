import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/prediction_service.dart';

/// What a user SAYS about her regularity, before the app has watched a single
/// cycle complete.
///
/// `_stdDev` returns 0 for fewer than two complete cycles, so the ± window sat
/// at the `max(1, ...)` floor for the first two to three months — a woman with
/// rock-steady cycles and one swinging 26→41 got an identical ±1 day estimate
/// for a quarter of a year, when she could have said which she was in one tap.
///
/// The rule the asserts below enforce is that a self-reported answer may only
/// ever SUBTRACT certainty. It widens the window and it can cap confidence, but
/// it never raises confidence and it never survives contact with real logged
/// cycles. `catalog.dart:405-417` states the asymmetry this follows: showing a
/// fertile window to somebody who has none is the app asserting something
/// false, while suppressing a real one costs information available elsewhere.
Cycle _cycle(DateTime start, {int? lengthDays}) => Cycle(
      start: start,
      end: start.add(const Duration(days: 4)),
      lengthDays: lengthDays,
    );

void main() {
  group('the catalog resolves an answer into numbers the predictor can take', () {
    test('every option maps to a prior, and a wider answer means a wider one',
        () {
      final priors = [
        for (final o in kCycleRegularityOptions)
          cycleVariabilityPriorFor(o.key),
      ];
      expect(priors, everyElement(isNotNull));
      expect(priors.length, 3);
      // Monotonic: "within a day or two" can never produce a window at least
      // as wide as "it varies a lot", whatever the numbers are tuned to.
      expect(priors[0]!, lessThan(priors[1]!));
      expect(priors[1]!, lessThan(priors[2]!));
    });

    test('an unanswered or unknown key yields no prior at all', () {
      // Null is "nobody asked", which is not the same as "regular". Defaulting
      // an unanswered question to the tightest window would invent precision.
      expect(cycleVariabilityPriorFor(null), isNull);
      expect(cycleVariabilityPriorFor('reg_from_a_future_version'), isNull);
    });

    test('only the irregular answer suppresses the fertile window', () {
      expect(cycleRegularityIsIrregular(kRegularityIrregular), isTrue);
      expect(cycleRegularityIsIrregular(kRegularityRoughly), isFalse);
      expect(cycleRegularityIsIrregular(kRegularityVeryRegular), isFalse);
      expect(cycleRegularityIsIrregular(null), isFalse);
    });
  });

  group('the prior in PredictionService', () {
    test('with nothing logged yet, the prior IS the window', () {
      final result = PredictionService.predict(
        [_cycle(DateTime(2026, 9, 1))],
        fallbackCycleLength: 28,
        variabilityPrior: 5,
        asOf: DateTime(2026, 9, 10),
      );

      expect(result.cycleVariabilityDays, 5);
      expect(result.nextPeriodWindowStart, DateTime(2026, 9, 24));
      expect(result.nextPeriodWindowEnd, DateTime(2026, 10, 4));
    });

    test('two real cycles beat the prior — logged data always wins', () {
      final result = PredictionService.predict(
        [
          _cycle(DateTime(2026, 6, 1), lengthDays: 24),
          _cycle(DateTime(2026, 6, 25), lengthDays: 38),
          _cycle(DateTime(2026, 8, 2)),
        ],
        fallbackCycleLength: 28,
        variabilityPrior: 1,
        asOf: DateTime(2026, 8, 10),
      );

      // stdDev([24, 38]) is about 9.9 — nothing like the 1 that was claimed.
      expect(result.cycleVariabilityDays, greaterThan(5));
    });

    test('a genuinely steady pair keeps its real zero rather than the prior',
        () {
      // The subtle one: `_stdDev` returns 0 both for "not enough data" and for
      // "two identical cycles". Only the first may be replaced by a prior, so
      // the gate has to be the COUNT and not the value.
      final result = PredictionService.predict(
        [
          _cycle(DateTime(2026, 6, 1), lengthDays: 28),
          _cycle(DateTime(2026, 6, 29), lengthDays: 28),
          _cycle(DateTime(2026, 7, 27)),
        ],
        fallbackCycleLength: 28,
        variabilityPrior: 5,
        asOf: DateTime(2026, 8, 1),
      );

      expect(result.cycleVariabilityDays, 0);
    });

    test('a prior never raises confidence: no cycles is still no confidence',
        () {
      final result = PredictionService.predict(
        [_cycle(DateTime(2026, 9, 1))],
        fallbackCycleLength: 28,
        variabilityPrior: 1,
        asOf: DateTime(2026, 9, 10),
      );

      expect(result.confidence, PredictionConfidence.none);
    });

    test('saying cycles vary a lot caps confidence and kills the fertile band',
        () {
      // Six tight cycles would otherwise earn HIGH. The self-reported answer
      // can only ever pull that down.
      final cycles = [
        for (var i = 0; i < 6; i++)
          _cycle(DateTime(2026, 1, 1).add(Duration(days: 28 * i)),
              lengthDays: 28),
        _cycle(DateTime(2026, 1, 1).add(const Duration(days: 28 * 6))),
      ];

      final honest = PredictionService.predict(cycles,
          fallbackCycleLength: 28, asOf: DateTime(2026, 6, 1));
      expect(honest.confidence, PredictionConfidence.high);

      final claimed = PredictionService.predict(cycles,
          fallbackCycleLength: 28,
          capConfidenceToLow: true,
          asOf: DateTime(2026, 6, 1));
      expect(claimed.confidence, PredictionConfidence.low);
    });
  });
}
