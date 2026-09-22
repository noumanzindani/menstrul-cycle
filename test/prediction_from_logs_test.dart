import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/prediction_service.dart';

/// The single recompute both the foreground (main.dart ProxyProvider) and the
/// background isolate (CheckInWriter) run: logs + the tracking mode -> a
/// prediction, with the mode-specific health suppressions applied in ONE place
/// so the two callers can never drift apart.
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

  // `count` regular 5-day periods, `cycleLen` apart, from `firstStart`.
  List<DailyLog> bleedingCycles(
    DateTime firstStart, {
    required int count,
    int cycleLen = 28,
    int periodLen = 5,
  }) {
    final logs = <DailyLog>[];
    var start = firstStart;
    for (var c = 0; c < count; c++) {
      for (var d = 0; d < periodLen; d++) {
        logs.add(log(start.add(Duration(days: d)), flow: FlowIntensity.medium));
      }
      start = start.add(Duration(days: cycleLen));
    }
    return logs;
  }

  final logs = bleedingCycles(DateTime(2026, 1, 1), count: 6);
  final asOf = DateTime(2026, 1, 1).add(const Duration(days: 28 * 5));

  test('track mode: derives cycles from logs and predicts a next period', () {
    final r = PredictionService.predictFromLogs(
      logs: logs,
      mode: TrackingMode.track,
      cycleLength: 28,
      periodLength: 5,
      asOf: asOf,
    );
    expect(r.hasPrediction, isTrue);
    expect(r.confidence, isNot(PredictionConfidence.none));
  });

  test('pregnancy mode: suppresses all period/fertility prediction', () {
    // Even with a rich bleeding history, pregnancy shows no next-period estimate.
    final r = PredictionService.predictFromLogs(
      logs: logs,
      mode: TrackingMode.pregnancy,
      cycleLength: 28,
      periodLength: 5,
      asOf: asOf,
    );
    expect(r.hasPrediction, isFalse);
  });

  // Structural, because the risk here is not a wrong answer but a MISSING one:
  // three separate call sites recompute this -- the foreground ProxyProvider,
  // the background isolate behind a notification action, and the home-widget
  // refresh -- and a fourth will appear eventually. One that forgets the gate
  // shows a fertile window the rest of the app suppresses, on the same data,
  // and nothing else in the suite would notice.
  /// Every argument that changes WHAT is predicted. A suppression is only as
  /// good as its least-wired caller, and a missed one is silent: the
  /// notification and the home widget would keep showing a fertile window the
  /// app itself had stopped showing. Add to this whenever the signature grows.
  const requiredArguments = [
    'contraceptionSuppressesOvulation:',
    'cycleVariabilityPrior:',
    'cyclesReportedIrregular:',
  ];

  test('GUARDRAIL: every predictFromLogs caller passes every prediction gate',
      () {
    final callers = <String>[];
    final missing = <String>[];
    // path -> the arguments it left out, so a failure names the gap rather
    // than only the file.
    final gaps = <String, List<String>>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      var from = 0;
      while (true) {
        final at = src.indexOf('PredictionService.predictFromLogs(', from);
        if (at < 0) break;
        from = at + 1;
        callers.add(f.path);
        // The argument list ends at the first ');' after the call opens; a
        // fixed line window would silently pass a call that grew longer.
        final end = src.indexOf(');', at);
        final args = end < 0 ? src.substring(at) : src.substring(at, end);
        final absent = [
          for (final a in requiredArguments)
            if (!args.contains(a)) a,
        ];
        if (absent.isNotEmpty) {
          missing.add(f.path);
          gaps[f.path] = absent;
        }
      }
    }

    expect(callers, hasLength(greaterThanOrEqualTo(3)),
        reason: 'the scan found almost nothing — it has stopped matching');
    expect(missing, isEmpty,
        reason: 'these recompute predictions from different inputs than the '
            'rest of the app: $gaps');
  });

  group('a signup regularity answer, before any cycle has completed', () {
    // One logged period is all the wizard leaves behind, so `_stdDev` has
    // nothing: without a prior every user got the `max(1, 0)` floor. The
    // window below is exactly what `_NextPeriodCard` prints as "± N days"
    // (home_screen.dart:646-648 takes `nextPeriodWindowEnd - nextPeriodStart`).
    final justOnePeriod = [
      for (var d = 0; d < 5; d++)
        log(DateTime(2026, 9, 1).add(Duration(days: d)),
            flow: FlowIntensity.medium),
    ];

    int windowFor({double? prior, bool irregular = false}) {
      final r = PredictionService.predictFromLogs(
        logs: justOnePeriod,
        mode: TrackingMode.track,
        cycleLength: 28,
        periodLength: 5,
        cycleVariabilityPrior: prior,
        cyclesReportedIrregular: irregular,
        asOf: DateTime(2026, 9, 10),
      );
      return r.nextPeriodWindowEnd!.difference(r.nextPeriodStart!).inDays;
    }

    test('unanswered keeps the floor it has always had', () {
      expect(windowFor(), 1);
    });

    test('each answer widens the window Home prints', () {
      expect(windowFor(prior: cycleVariabilityPriorFor(kRegularityVeryRegular)),
          1);
      expect(windowFor(prior: cycleVariabilityPriorFor(kRegularityRoughly)), 2);
      expect(windowFor(prior: cycleVariabilityPriorFor(kRegularityIrregular)),
          5);
    });

    test('the irregular answer also removes the fertile window', () {
      final r = PredictionService.predictFromLogs(
        logs: justOnePeriod,
        mode: TrackingMode.track,
        cycleLength: 28,
        periodLength: 5,
        cycleVariabilityPrior: cycleVariabilityPriorFor(kRegularityIrregular),
        cyclesReportedIrregular: true,
        asOf: DateTime(2026, 9, 10),
      );
      // `fertilityBand` is gated to medium+, so a capped confidence is what
      // suppresses the band app-wide rather than a second switch.
      expect(r.fertilityConfidence.index,
          lessThanOrEqualTo(PredictionConfidence.low.index));
    });
  });

  group('hormonal contraception suppresses the fertile window', () {
    // The same suppression perimenopause gets, for a different reason: someone
    // on a method in `kOvulationSuppressingContraception` does not ovulate, so
    // a predicted fertile window is the app asserting something false about
    // their body. Capping confidence to low is what self-suppresses the
    // ovulation marker and the fertility band app-wide.
    test('a suppressing method caps confidence to low', () {
      final r = PredictionService.predictFromLogs(
        logs: logs,
        mode: TrackingMode.track,
        cycleLength: 28,
        periodLength: 5,
        asOf: asOf,
        contraceptionSuppressesOvulation:
            contraceptionSuppressesOvulation('contra_combined_pill'),
      );
      expect(r.confidence, PredictionConfidence.low);
      // The cap is not cosmetic: `fertilityBand` returns `none` for low
      // confidence, which is what actually removes the band from the calendar,
      // the ring and the home card.
      expect(
        PredictionService.fertilityBand(
          today: r.ovulationDay ?? asOf,
          ovulation: r.ovulationDay,
          fertileWindowStart: r.fertileWindowStart,
          fertileWindowEnd: r.fertileWindowEnd,
          confidence: r.confidence,
        ),
        FertilityBand.none,
      );
    });

    test('a non-hormonal method does NOT suppress it', () {
      // The copper IUD is the case that proves the gate discriminates rather
      // than firing on "any contraception answered". Ovulation continues, so
      // blanking the window would remove a real signal.
      final r = PredictionService.predictFromLogs(
        logs: logs,
        mode: TrackingMode.track,
        cycleLength: 28,
        periodLength: 5,
        asOf: asOf,
        contraceptionSuppressesOvulation:
            contraceptionSuppressesOvulation('contra_copper_iud'),
      );
      expect(r.confidence, isNot(PredictionConfidence.low));
    });

    test('never asked reads as no suppression', () {
      expect(contraceptionSuppressesOvulation(null), isFalse);
      expect(contraceptionSuppressesOvulation(kContraceptionNone), isFalse);
      // An answer written by a newer build is unknown here, and unknown must
      // not suppress -- silently blanking the fertile window on a value this
      // build cannot read would be a change nobody could explain.
      expect(contraceptionSuppressesOvulation('contra_from_the_future'),
          isFalse);
    });

    test('still predicts the next period -- only fertility is suppressed', () {
      final r = PredictionService.predictFromLogs(
        logs: logs,
        mode: TrackingMode.track,
        cycleLength: 28,
        periodLength: 5,
        asOf: asOf,
        contraceptionSuppressesOvulation: true,
      );
      expect(r.hasPrediction, isTrue,
          reason: 'a bleed on the pill is still a bleed worth predicting');
    });
  });

  test('perimenopause mode: caps confidence to low (suppresses fertility)', () {
    final r = PredictionService.predictFromLogs(
      logs: logs,
      mode: TrackingMode.perimenopause,
      cycleLength: 28,
      periodLength: 5,
      asOf: asOf,
    );
    expect(r.confidence, PredictionConfidence.low);
  });
}
