import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/services/insights_narrator.dart';

/// Plain-language "Your patterns" narratives over the user's own data. Pure and
/// deterministic. Descriptive, never diagnostic; hedged; gated on enough data so
/// thin logs never produce false precision; never the word "safe".
void main() {
  // Cycles are oldest -> newest; the last one is left open (lengthDays == null),
  // mirroring how CycleCalculator returns them.
  List<Cycle> cyclesFromLengths(List<int> lengths,
      {DateTime? first, int periodLen = 5}) {
    final start0 = first ?? DateTime(2026, 1, 1);
    final cycles = <Cycle>[];
    var start = start0;
    for (final len in lengths) {
      cycles.add(Cycle(
          start: start,
          end: start.add(Duration(days: periodLen - 1)),
          lengthDays: len));
      start = start.add(Duration(days: len));
    }
    // Trailing open cycle (no known next start).
    cycles.add(Cycle(start: start, end: start.add(Duration(days: periodLen - 1))));
    return cycles;
  }

  DailyLog log(DateTime date, {String symptoms = '{}'}) => DailyLog(
        id: 0,
        date: date,
        flow: null,
        symptoms: symptoms,
        mood: null,
        notes: null,
        bbt: null,
        opk: null,
        createdAt: date,
        updatedAt: date,
      );

  String keyOf(List<CycleNarrative> ns, String key) =>
      ns.firstWhere((n) => n.key == key,
          orElse: () => const CycleNarrative('', '')).text;
  bool has(List<CycleNarrative> ns, String key) => ns.any((n) => n.key == key);

  group('regularity', () {
    test('very regular when variability is tiny', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([28, 28, 28]), logs: const []);
      expect(keyOf(ns, 'regularity'), contains('very regular'));
    });

    test('fairly regular for moderate variability', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([26, 28, 30]), logs: const []);
      expect(keyOf(ns, 'regularity'), contains('fairly regular'));
    });

    test('needs at least 3 complete cycles', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([28, 28]), logs: const []);
      expect(has(ns, 'regularity'), isFalse);
    });

    test('stays silent when cycles vary a lot (the red-flag speaks instead)', () {
      // stdDev of [21, 28, 35] ~= 7 boundary; [20, 28, 40] is clearly > 7.
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([20, 28, 40]), logs: const []);
      expect(has(ns, 'regularity'), isFalse);
    });
  });

  group('cycle-length trend (recent 3 vs earlier)', () {
    test('flags cycles running shorter', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([29, 29, 27, 27, 27]), logs: const []);
      expect(keyOf(ns, 'cycle_trend'), contains('shorter'));
      expect(keyOf(ns, 'cycle_trend'), contains('2 days'));
    });

    test('flags cycles running longer', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([27, 27, 30, 30, 30]), logs: const []);
      expect(keyOf(ns, 'cycle_trend'), contains('longer'));
    });

    test('no trend when recent matches earlier', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([28, 28, 28, 28, 28]), logs: const []);
      expect(has(ns, 'cycle_trend'), isFalse);
    });

    test('needs at least 5 complete cycles', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([30, 30, 24, 24]), logs: const []);
      expect(has(ns, 'cycle_trend'), isFalse);
    });
  });

  group('current phase', () {
    test('describes the day and phase when provided', () {
      final ns = InsightsNarrator.narrate(
        cycles: cyclesFromLengths([28, 28, 28]),
        logs: const [],
        currentCycleDay: 18,
        currentPhase: CyclePhase.luteal,
      );
      final t = keyOf(ns, 'phase');
      expect(t, contains('18'));
      expect(t.toLowerCase(), contains('luteal'));
    });

    test('absent when no current phase is supplied (e.g. the PDF path)', () {
      final ns = InsightsNarrator.narrate(
          cycles: cyclesFromLengths([28, 28, 28]), logs: const []);
      expect(has(ns, 'phase'), isFalse);
    });

    test('absent for unknown phase', () {
      final ns = InsightsNarrator.narrate(
        cycles: cyclesFromLengths([28, 28, 28]),
        logs: const [],
        currentCycleDay: 3,
        currentPhase: CyclePhase.unknown,
      );
      expect(has(ns, 'phase'), isFalse);
    });
  });

  group('symptom <-> phase correlation', () {
    // One complete 28-day cycle from Jan 1 (period Jan1-5). Luteal = index > 15,
    // i.e. Jan 17 onward.
    List<Cycle> oneCycle() => [
          Cycle(
              start: DateTime(2026, 1, 1),
              end: DateTime(2026, 1, 5),
              lengthDays: 28),
          Cycle(start: DateTime(2026, 1, 29), end: DateTime(2026, 2, 2)),
        ];

    test('surfaces a symptom that clusters in one phase', () {
      final ns = InsightsNarrator.narrate(
        cycles: oneCycle(),
        logs: [
          log(DateTime(2026, 1, 20), symptoms: '{"headache":true}'),
          log(DateTime(2026, 1, 22), symptoms: '{"headache":true}'),
          log(DateTime(2026, 1, 24), symptoms: '{"headache":true}'),
        ],
      );
      final t = keyOf(ns, 'symptom_phase');
      expect(t.toLowerCase(), contains('headache'));
      expect(t.toLowerCase(), contains('luteal'));
    });

    test('needs at least 3 logged occurrences', () {
      final ns = InsightsNarrator.narrate(
        cycles: oneCycle(),
        logs: [
          log(DateTime(2026, 1, 20), symptoms: '{"headache":true}'),
          log(DateTime(2026, 1, 22), symptoms: '{"headache":true}'),
        ],
      );
      expect(has(ns, 'symptom_phase'), isFalse);
    });

    test('no cluster when the symptom is spread across phases', () {
      final ns = InsightsNarrator.narrate(
        cycles: oneCycle(),
        logs: [
          log(DateTime(2026, 1, 3), symptoms: '{"headache":true}'), // menstrual
          log(DateTime(2026, 1, 10), symptoms: '{"headache":true}'), // follicular
          log(DateTime(2026, 1, 20), symptoms: '{"headache":true}'), // luteal
          log(DateTime(2026, 1, 22), symptoms: '{"headache":true}'), // luteal
        ],
      );
      expect(has(ns, 'symptom_phase'), isFalse);
    });
  });

  group('ordering & empty', () {
    test('trend leads the list (Home shows the most notable first)', () {
      final ns = InsightsNarrator.narrate(
        cycles: cyclesFromLengths([29, 29, 27, 27, 27]),
        logs: const [],
        currentCycleDay: 18,
        currentPhase: CyclePhase.luteal,
      );
      expect(ns.first.key, 'cycle_trend');
    });

    test('no cycles and no phase -> no narratives', () {
      final ns = InsightsNarrator.narrate(cycles: const [], logs: const []);
      expect(ns, isEmpty);
    });
  });
}
