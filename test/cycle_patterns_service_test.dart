import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/cycle_patterns_service.dart';

/// Pure, descriptive pattern cards for Insights. Every one is gated on enough
/// data, reads only COMPLETE cycles for phase attribution, and never claims a
/// cause, a score or a fertility probability.
void main() {
  final day0 = DateTime(2026, 1, 1);
  DateTime d(int i) => day0.add(Duration(days: i));

  /// [n] complete 28-day cycles with 5-day periods, plus an open one after.
  /// Phase map for a 28-day cycle (luteal = 14): idx 0–4 period, 13–15 fertile
  /// window, 16+ luteal, everything else follicular.
  List<Cycle> cycles(int n, {int len = 28, int period = 5}) => [
        for (var c = 0; c < n; c++)
          Cycle(
            start: d(c * len),
            end: d(c * len + period - 1),
            lengthDays: len,
          ),
        Cycle(start: d(n * len), end: d(n * len + period - 1)),
      ];

  DailyLog log(
    DateTime date, {
    Map<String, Object> tags = const {},
    FlowIntensity? flow,
    String? mood,
    String? opk,
  }) =>
      DailyLog(
        id: 0,
        date: date,
        flow: flow,
        symptoms: jsonEncode(tags),
        mood: mood,
        notes: null,
        bbt: null,
        opk: opk,
        createdAt: date,
        updatedAt: date,
      );

  group('phase profile', () {
    List<DailyLog> energyLogs(int nCycles) => [
          for (var c = 0; c < nCycles; c++) ...[
            for (final i in [0, 1, 2]) log(d(c * 28 + i), tags: {'energy': 2}),
            for (final i in [6, 7, 8]) log(d(c * 28 + i), tags: {'energy': 4}),
          ],
        ];

    test('needs two complete cycles', () {
      expect(
          CyclePatternsService.phaseProfile(cycles(1), energyLogs(1)), isNull);
    });

    test('averages a 1–5 metric per phase', () {
      final p = CyclePatternsService.phaseProfile(cycles(2), energyLogs(2))!;
      final energy = p.rows.firstWhere((r) => r.label == 'Energy');
      expect(energy.cells[CyclePhase.menstrual], '2.0');
      expect(energy.cells[CyclePhase.follicular], '4.0');
    });

    test('a phase with fewer than 3 readings shows no value', () {
      final logs = [
        ...energyLogs(2),
        log(d(20), tags: {'energy': 5}), // one luteal reading
        log(d(21), tags: {'energy': 5}), // two
      ];
      final p = CyclePatternsService.phaseProfile(cycles(2), logs)!;
      final energy = p.rows.firstWhere((r) => r.label == 'Energy');
      expect(energy.cells.containsKey(CyclePhase.luteal), isFalse);
    });

    test('0 means unset and is never averaged in', () {
      final logs = [
        ...energyLogs(2),
        for (final i in [9, 10, 11]) log(d(i), tags: {'energy': 0}),
      ];
      final p = CyclePatternsService.phaseProfile(cycles(2), logs)!;
      final energy = p.rows.firstWhere((r) => r.label == 'Energy');
      expect(energy.cells[CyclePhase.follicular], '4.0');
    });

    test('days in the open cycle are not attributed to a phase', () {
      final logs = [
        ...energyLogs(2),
        // Open cycle starts at day 56: these would be "period" if counted.
        for (final i in [56, 57, 58, 59]) log(d(i), tags: {'energy': 5}),
      ];
      final p = CyclePatternsService.phaseProfile(cycles(2), logs)!;
      final energy = p.rows.firstWhere((r) => r.label == 'Energy');
      expect(energy.cells[CyclePhase.menstrual], '2.0');
    });

    test('sleep hours carry a unit', () {
      final logs = [
        for (var c = 0; c < 2; c++) ...[
          for (final i in [0, 1]) log(d(c * 28 + i), tags: {'sleep': 6}),
          for (final i in [20, 21]) log(d(c * 28 + i), tags: {'sleep': 8}),
        ],
      ];
      final p = CyclePatternsService.phaseProfile(cycles(2), logs)!;
      final sleep = p.rows.firstWhere((r) => r.label == 'Sleep');
      expect(sleep.cells[CyclePhase.menstrual], '6.0 h');
      expect(sleep.cells[CyclePhase.luteal], '8.0 h');
    });

    test('mood shows the most-logged mood per phase', () {
      final logs = [
        for (var c = 0; c < 2; c++) ...[
          for (final i in [0, 1]) log(d(c * 28 + i), mood: 'sad'),
          for (final i in [20, 21]) log(d(c * 28 + i), mood: 'calm'),
        ],
      ];
      final p = CyclePatternsService.phaseProfile(cycles(2), logs)!;
      final mood = p.rows.firstWhere((r) => r.label == 'Mood');
      expect(mood.cells[CyclePhase.menstrual], 'Low');
      expect(mood.cells[CyclePhase.luteal], 'Calm');
    });

    test('libido reads the retired high-libido key too', () {
      final logs = [
        for (var c = 0; c < 2; c++) ...[
          for (final i in [0, 1]) log(d(c * 28 + i), tags: {kLibidoLow: true}),
          for (final i in [13, 14])
            log(d(c * 28 + i), tags: {kLegacyHighLibidoKey: true}),
        ],
      ];
      final p = CyclePatternsService.phaseProfile(cycles(2), logs)!;
      final libido = p.rows.firstWhere((r) => r.label == 'Libido');
      expect(libido.cells[CyclePhase.menstrual], 'Low');
      expect(libido.cells[CyclePhase.ovulatory], 'High');
    });

    test('a metric known in only one phase is dropped', () {
      final logs = [
        for (var c = 0; c < 2; c++)
          for (final i in [0, 1]) log(d(c * 28 + i), tags: {'stress': 4}),
      ];
      expect(CyclePatternsService.phaseProfile(cycles(2), logs), isNull);
    });
  });

  group('pain', () {
    test('needs two periods with pain logged', () {
      final logs = [log(d(1), tags: {'pain': 6})];
      expect(
          CyclePatternsService.painSummary(cycles(2), logs, asOf: d(60)),
          isNull);
    });

    test('worst pain per period, newest first, with the average', () {
      final logs = [
        log(d(0), tags: {'pain': 4}),
        log(d(1), tags: {'pain': 6}),
        log(d(28), tags: {'pain': 8}),
        log(d(56), tags: {'pain': 7}), // the open cycle's period counts
      ];
      final s = CyclePatternsService.painSummary(cycles(2), logs, asOf: d(60))!;
      expect(s.periods.map((p) => p.worst), [7, 8, 6]);
      expect(s.periods.first.start, d(56));
      expect(s.averageWorst, 7.0);
    });

    test('counts days at 7/10 or more in the last 90 days, any cycle day', () {
      final logs = [
        log(d(0), tags: {'pain': 9}), // older than 90 days before asOf
        log(d(1), tags: {'pain': 5}),
        log(d(28), tags: {'pain': 7}),
        log(d(40), tags: {'pain': 8}), // outside the period, still counted
      ];
      final s =
          CyclePatternsService.painSummary(cycles(2), logs, asOf: d(100))!;
      expect(s.severeDays, 2);
    });
  });

  group('early warning', () {
    // Next starts for 3 complete cycles are days 28, 56 and 84.
    List<DailyLog> headacheBefore(List<int> nextStarts, int daysBefore) => [
          for (final s in nextStarts)
            for (var k = daysBefore; k >= 1; k--)
              log(d(s - k), tags: {'headache': true}),
        ];

    test('names a symptom that starts a set number of days before', () {
      final w = CyclePatternsService.earlyWarnings(
          cycles(3), headacheBefore([28, 56, 84], 2));
      expect(w, hasLength(1));
      expect(w.single.daysBefore, 2);
      expect(w.single.seen, 3);
      expect(w.single.text, contains('Headache'));
      expect(w.single.text, contains('2 days before your period'));
    });

    test('needs to be seen in at least 3 cycles', () {
      final w = CyclePatternsService.earlyWarnings(
          cycles(3), headacheBefore([28, 56], 2));
      expect(w, isEmpty);
    });

    test('reads digestion, skin and urine tags too', () {
      final logs = [
        for (final s in [28, 56, 84]) log(d(s - 3), tags: {'dig_gas': true}),
      ];
      final w = CyclePatternsService.earlyWarnings(cycles(3), logs);
      expect(w.single.text, contains('Gas'));
      expect(w.single.daysBefore, 3);
    });

    test('never more than three', () {
      final keys = ['headache', 'cramps', 'bloating', 'acne', 'backache'];
      final logs = [
        for (final s in [28, 56, 84])
          log(d(s - 1), tags: {for (final k in keys) k: true}),
      ];
      expect(CyclePatternsService.earlyWarnings(cycles(3), logs).length, 3);
    });
  });

  group('period shape', () {
    List<DailyLog> period(int start) => [
          log(d(start), flow: FlowIntensity.light),
          log(d(start + 1), flow: FlowIntensity.heavy),
          log(d(start + 2), flow: FlowIntensity.medium),
          log(d(start + 3), flow: FlowIntensity.light),
          log(d(start + 4), flow: FlowIntensity.spotting),
        ];

    test('needs three finished periods', () {
      expect(
          CyclePatternsService.periodShape(
              cycles(2), [...period(0), ...period(28)]),
          isNull);
    });

    test('heaviest day, usual length and a typical flow per day', () {
      final s = CyclePatternsService.periodShape(
          cycles(3), [...period(0), ...period(28), ...period(56)])!;
      expect(s.heaviestDay, 2);
      expect(s.typicalLength, 5);
      expect(s.typicalByDay, [
        FlowIntensity.light,
        FlowIntensity.heavy,
        FlowIntensity.medium,
        FlowIntensity.light,
        FlowIntensity.spotting,
      ]);
      expect(s.text, contains('heaviest on day 2'));
    });
  });

  group('fertility signs', () {
    test('the cycle days positive ovulation tests fell on', () {
      final logs = [
        log(d(13), opk: 'positive'),
        log(d(28 + 14), opk: 'peak'),
        log(d(56 + 15), opk: 'positive'),
        log(d(56 + 10), opk: 'negative'),
      ];
      final s = CyclePatternsService.fertilitySigns(cycles(3), logs)!;
      expect(s.opkDays, (14, 16)); // 1-based cycle days
      expect(s.opkText, contains('cycle days 14–16'));
    });

    test('one cycle is not a pattern', () {
      final logs = [log(d(13), opk: 'positive')];
      expect(CyclePatternsService.fertilitySigns(cycles(3), logs), isNull);
    });

    test('egg-white and watery mucus days', () {
      final logs = [
        log(d(12), tags: {'cm_eggwhite': true}),
        log(d(28 + 11), tags: {'cm_watery': true}),
        log(d(28 + 3), tags: {'cm_dry': true}),
      ];
      final s = CyclePatternsService.fertilitySigns(cycles(3), logs)!;
      expect(s.mucusDays, (12, 13));
      expect(s.opkDays, isNull);
    });

    test('never uses the word safe', () {
      final logs = [
        log(d(13), opk: 'positive'),
        log(d(28 + 14), opk: 'positive'),
        log(d(12), tags: {'cm_eggwhite': true}),
        log(d(28 + 11), tags: {'cm_eggwhite': true}),
      ];
      final s = CyclePatternsService.fertilitySigns(cycles(3), logs)!;
      expect('${s.opkText} ${s.mucusText}'.toLowerCase(),
          isNot(contains('safe')));
    });
  });

  group('lifestyle', () {
    List<DailyLog> dataset({int alcoholDays = 8, int crampsWith = 6}) => [
          for (var i = 0; i < alcoholDays; i++)
            log(d(i), tags: {
              'habit_alcohol': true,
              if (i < crampsWith) 'cramps': true,
            }),
          for (var i = 0; i < 40; i++)
            log(d(100 + i), tags: {if (i < 2) 'cramps': true}),
        ];

    test('reports a symptom logged far more often alongside a habit', () {
      final links = CyclePatternsService.lifestyleLinks(dataset());
      expect(links, hasLength(1));
      final l = links.single;
      expect(l.text, contains('cramps on 6 of 8 days you logged alcohol'));
      expect(l.text, contains('2 of 40 other days'));
    });

    test('needs at least 5 days of the habit', () {
      expect(
          CyclePatternsService.lifestyleLinks(
              dataset(alcoholDays: 4, crampsWith: 4)),
          isEmpty);
    });

    test('a small difference is not reported', () {
      final logs = [
        for (var i = 0; i < 10; i++)
          log(d(i), tags: {'habit_caffeine': true, if (i < 3) 'cramps': true}),
        for (var i = 0; i < 10; i++)
          log(d(50 + i), tags: {if (i < 2) 'cramps': true}),
      ];
      expect(CyclePatternsService.lifestyleLinks(logs), isEmpty);
    });

    test('never claims a cause', () {
      final text = CyclePatternsService.lifestyleLinks(dataset()).single.text;
      for (final w in ['cause', 'because', 'trigger', 'leads to']) {
        expect(text.toLowerCase(), isNot(contains(w)));
      }
    });
  });

  group('coverage', () {
    test('counts complete cycles, logged days and the first day', () {
      final logs = [log(d(3)), log(d(1)), log(d(40))];
      final c = CyclePatternsService.coverage(cycles(2), logs)!;
      expect(c.completeCycles, 2);
      expect(c.loggedDays, 3);
      expect(c.since, d(1));
      expect(c.text, contains('2 complete cycles'));
      expect(c.text, contains('3 logged days'));
    });

    test('nothing logged, nothing to say', () {
      expect(CyclePatternsService.coverage(const [], const []), isNull);
    });
  });
}
