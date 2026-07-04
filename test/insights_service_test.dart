import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/services/insights_service.dart';

List<Cycle> _cycles(List<int> lengths, {int periodLen = 5}) {
  final cycles = <Cycle>[];
  var start = DateTime(2026, 1, 1);
  for (var i = 0; i < lengths.length; i++) {
    cycles.add(Cycle(
      start: start,
      end: start.add(Duration(days: periodLen - 1)),
      lengthDays: lengths[i],
    ));
    start = start.add(Duration(days: lengths[i]));
  }
  // Trailing open cycle so `lengths` map 1:1 to complete cycles.
  cycles.add(Cycle(
      start: start, end: start.add(Duration(days: periodLen - 1)), lengthDays: null));
  return cycles;
}

void main() {
  test('empty history has no data and no flags', () {
    final r = InsightsService.analyze([]);
    expect(r.stats.hasData, isFalse);
    expect(r.flags, isEmpty);
  });

  test('regular history: stats correct, no flags', () {
    final r = InsightsService.analyze(_cycles([28, 28, 29, 27]),
        asOf: DateTime(2026, 5, 1));
    expect(r.stats.cyclesTracked, 4);
    expect(r.stats.averageCycleLength, 28);
    expect(r.stats.shortestCycle, 27);
    expect(r.stats.longestCycle, 29);
    expect(r.flags, isEmpty);
  });

  test('short and long cycles raise gentle flags', () {
    final r = InsightsService.analyze(_cycles([19, 40, 28]),
        asOf: DateTime(2026, 4, 1));
    final titles = r.flags.map((f) => f.title).toList();
    expect(titles, contains('Some cycles are short'));
    expect(titles, contains('Some cycles are long'));
  });

  test('long period raises a flag', () {
    final r = InsightsService.analyze(_cycles([28, 28], periodLen: 9),
        asOf: DateTime(2026, 3, 1));
    expect(r.flags.map((f) => f.title), contains('Some periods last over a week'));
  });

  test('90+ days since last period raises amenorrhea awareness', () {
    // Last cycle starts far in the past relative to asOf.
    final r = InsightsService.analyze(_cycles([28]),
        asOf: DateTime(2026, 12, 31));
    expect(r.flags.map((f) => f.title),
        contains('No period logged in a while'));
  });
}
