import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/cycle_calculator.dart';
import 'package:menstrul_track/services/insights_service.dart';

/// Tier 2 red flags, surfaced through the EXISTING pattern-nudge machinery
/// rather than a parallel one: same conservative posture, same non-diagnostic
/// wording, same place on the Insights screen.
///
/// Two of the four need no new question at all — intermenstrual bleeding and
/// pelvic pain outside the period are derived from days the user already logs.
/// The other two (bleeding after sex, heavy-bleeding markers) cannot be
/// derived from anything and are new day tags.
DailyLog _log(
  DateTime date, {
  FlowIntensity? flow,
  Set<String> flags = const {},
  Map<String, num> numbers = const {},
}) =>
    DailyLog(
      id: 0,
      date: date,
      flow: flow,
      symptoms: encodeDayTags(flags: flags, numbers: numbers),
      createdAt: date,
      updatedAt: date,
    );

/// A normal period: five medium days starting on [start].
List<DailyLog> _period(DateTime start) => [
      for (var i = 0; i < 5; i++)
        _log(start.add(Duration(days: i)), flow: FlowIntensity.medium),
    ];

Set<String> _keys(List<DailyLog> logs) => {
      for (final n in InsightsService.patternNudges(
        cycles: CycleCalculator.computeCycles(logs),
        logs: logs,
      ))
        n.key,
    };

void main() {
  group('bleeding between periods (derived)', () {
    test('spotting a fortnight into two cycles is surfaced', () {
      final logs = [
        ..._period(DateTime(2026, 1, 1)),
        _log(DateTime(2026, 1, 15), flow: FlowIntensity.spotting),
        ..._period(DateTime(2026, 1, 29)),
        _log(DateTime(2026, 2, 12), flow: FlowIntensity.spotting),
        ..._period(DateTime(2026, 2, 26)),
      ];
      expect(_keys(logs), contains('intermenstrual'));
    });

    test('ordinary periods alone never trip it', () {
      final logs = [
        ..._period(DateTime(2026, 1, 1)),
        ..._period(DateTime(2026, 1, 29)),
        ..._period(DateTime(2026, 2, 26)),
      ];
      expect(_keys(logs), isNot(contains('intermenstrual')));
    });

    test('a SINGLE episode does not trip it', () {
      // A false alarm about bleeding is worse than a miss: it sends somebody to
      // a clinician over one logged day, and the app's whole posture is that a
      // pattern, not an incident, is what is worth mentioning.
      final logs = [
        ..._period(DateTime(2026, 1, 1)),
        _log(DateTime(2026, 1, 15), flow: FlowIntensity.spotting),
        ..._period(DateTime(2026, 1, 29)),
      ];
      expect(_keys(logs), isNot(contains('intermenstrual')));
    });

    test('a light period that is ALL spotting is not intermenstrual bleeding',
        () {
      // Four spotting days at a normal interval are somebody's period, not
      // bleeding between periods. The run's length and spacing are what
      // separate the two.
      final logs = [
        for (var i = 0; i < 4; i++)
          _log(DateTime(2026, 1, 1).add(Duration(days: i)),
              flow: FlowIntensity.spotting),
        for (var i = 0; i < 4; i++)
          _log(DateTime(2026, 1, 29).add(Duration(days: i)),
              flow: FlowIntensity.spotting),
        for (var i = 0; i < 4; i++)
          _log(DateTime(2026, 2, 26).add(Duration(days: i)),
              flow: FlowIntensity.spotting),
      ];
      expect(_keys(logs), isNot(contains('intermenstrual')));
    });
  });

  group('pelvic pain outside the period (derived)', () {
    test('recurrent pelvic pain away from bleeding days is surfaced', () {
      final logs = [
        ..._period(DateTime(2026, 1, 1)),
        _log(DateTime(2026, 1, 14), flags: {'pelvic_pain'}),
        ..._period(DateTime(2026, 1, 29)),
        _log(DateTime(2026, 2, 11), flags: {'pelvic_pain'}),
        ..._period(DateTime(2026, 2, 26)),
        _log(DateTime(2026, 3, 11), flags: {'pelvic_pain'}),
      ];
      expect(_keys(logs), contains('pelvic_pain_outside'));
    });

    test('pelvic pain ON period days is not surfaced as being outside it', () {
      // Period pain is already covered by the severe-pain nudge. Reporting it
      // twice, once under a heading that says "outside your period", would be
      // telling the user something untrue about their own log.
      final logs = [
        ..._period(DateTime(2026, 1, 1)),
        _log(DateTime(2026, 1, 1), flow: FlowIntensity.medium,
            flags: {'pelvic_pain'}),
        ..._period(DateTime(2026, 1, 29)),
        _log(DateTime(2026, 1, 30), flow: FlowIntensity.medium,
            flags: {'pelvic_pain'}),
        ..._period(DateTime(2026, 2, 26)),
        _log(DateTime(2026, 2, 27), flow: FlowIntensity.medium,
            flags: {'pelvic_pain'}),
      ];
      expect(_keys(logs), isNot(contains('pelvic_pain_outside')));
    });
  });

  group('flags that cannot be derived', () {
    test('bleeding after sex is surfaced from a single day', () {
      // The only flag here with a threshold of one. It is the single most
      // significant item on the Tier 2 list, and unlike the others there is no
      // benign reading of it that a pattern would rule out.
      final logs = [
        ..._period(DateTime(2026, 1, 1)),
        _log(DateTime(2026, 1, 14), flags: {'shx_post_coital'}),
      ];
      expect(_keys(logs), contains('post_coital'));
    });

    test('heavy-bleeding markers are surfaced after a pattern', () {
      final once = [
        ..._period(DateTime(2026, 1, 1)),
        _log(DateTime(2026, 1, 2), flow: FlowIntensity.heavy,
            flags: {kSymptomLargeClots}),
      ];
      expect(_keys(once), isNot(contains('heavy_bleeding')));

      final twice = [
        ...once,
        ..._period(DateTime(2026, 1, 29)),
        _log(DateTime(2026, 1, 30), flow: FlowIntensity.heavy,
            flags: {kSymptomSoakingHourly}),
      ];
      expect(_keys(twice), contains('heavy_bleeding'));
    });
  });

  test('every new nudge points at a clinician and diagnoses nothing', () {
    final logs = [
      ..._period(DateTime(2026, 1, 1)),
      _log(DateTime(2026, 1, 14), flags: {'shx_post_coital', 'pelvic_pain'}),
      _log(DateTime(2026, 1, 15), flow: FlowIntensity.spotting),
      ..._period(DateTime(2026, 1, 29)),
      _log(DateTime(2026, 2, 11), flags: {'pelvic_pain'}),
      _log(DateTime(2026, 2, 12), flow: FlowIntensity.spotting),
      ..._period(DateTime(2026, 2, 26)),
      _log(DateTime(2026, 3, 11), flags: {'pelvic_pain'}),
    ];
    final nudges = InsightsService.patternNudges(
      cycles: CycleCalculator.computeCycles(logs),
      logs: logs,
    );
    final mine = nudges.where((n) => const {
          'intermenstrual',
          'pelvic_pain_outside',
          'post_coital',
        }.contains(n.key));
    expect(mine, isNotEmpty);
    for (final n in mine) {
      expect(n.message.toLowerCase(), contains('clinician'),
          reason: '${n.key} must point at a human, not conclude anything');
      // The app never tells somebody they have a condition. Existing nudges
      // name conditions only as one possible cause ("one of them is PCOS");
      // an assertion is a different sentence entirely.
      expect(n.message.toLowerCase(), isNot(contains('you have')));
      expect(n.title.toLowerCase(), isNot(contains('cancer')));
    }
  });
}
