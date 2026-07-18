import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/cycle_overview_service.dart';

/// Aggregates one cycle's raw day logs into a single rollup: bleeding, symptoms,
/// emotions/mood, pain, lifestyle, and notes. Pure function of (cycle, logs),
/// scoped to the cycle's span [start, nextStart). Descriptive only.
void main() {
  DailyLog log(
    DateTime date, {
    FlowIntensity? flow,
    String symptoms = '{}',
    String? mood,
    String? notes,
  }) =>
      DailyLog(
        id: 0,
        date: date,
        flow: flow,
        symptoms: symptoms,
        mood: mood,
        notes: notes,
        bbt: null,
        opk: null,
        createdAt: date,
        updatedAt: date,
      );

  test('rolls up one cycle across all categories, excluding other cycles', () {
    final cycle = Cycle(
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 1, 3), // period days
      lengthDays: 28, // next cycle starts Jan 29
    );
    final logs = [
      log(DateTime(2026, 1, 1),
          flow: FlowIntensity.heavy,
          symptoms: encodeDayTags(
              flags: {'cramps', 'low_mood', 'habit_exercise'},
              numbers: {kMetricPain: 6}),
          mood: 'sad',
          notes: 'rough day'),
      log(DateTime(2026, 1, 2),
          flow: FlowIntensity.medium,
          symptoms: encodeDayTags(flags: {'cramps'})),
      log(DateTime(2026, 1, 3), flow: FlowIntensity.light),
      // Mid-cycle (still inside this cycle: before Jan 29).
      log(DateTime(2026, 1, 10),
          symptoms: encodeDayTags(
              flags: {'headache'}, numbers: {kMetricPain: 4})),
      // Next cycle — must be excluded from this rollup.
      log(DateTime(2026, 2, 1),
          flow: FlowIntensity.heavy,
          symptoms: encodeDayTags(flags: {'cramps'})),
    ];

    final o = CycleOverviewService.summarize(cycle, logs);

    expect(o.cycleLength, 28);
    expect(o.periodLength, 3);
    expect(o.bleedingDays, 3);
    expect(o.peakFlow, FlowIntensity.heavy);

    // Physical symptoms ranked; cramps twice (Jan 1 + Jan 2), headache once.
    expect(o.symptoms.first.label, 'Cramps');
    expect(o.symptoms.first.count, 2);
    expect(o.symptoms.any((s) => s.label == 'Headache' && s.count == 1), isTrue);
    // The Feb 1 cramps log is in the next cycle, so cramps stays at 2.

    // Emotions: an emotional symptom (Low mood) + a mood (Low).
    expect(o.emotions.any((e) => e.label == 'Low mood'), isTrue);
    expect(o.emotions.any((e) => e.label == 'Low'), isTrue);

    // Pain across the two days that logged it.
    expect(o.painAverage, closeTo(5.0, 0.001));
    expect(o.painPeak, 6);

    // Lifestyle + notes.
    expect(o.lifestyle.any((l) => l.label == 'Exercise' && l.count == 1), isTrue);
    expect(o.notesCount, 1);
  });
}
