import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/symptom_analysis_service.dart';

/// Per-symptom frequency + pain severity over the user's logs. Pure function of
/// the day-tags JSON: each symptom counts once per day, ranked most-logged
/// first; the 0–10 pain metric yields an average + peak. Reserved/namespaced
/// keys (sex, cervical mucus, habits) never surface — [decodeSymptoms] filters
/// them, matching the doctor PDF's symptom list.
void main() {
  DailyLog log(DateTime date, String symptoms) => DailyLog(
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

  test('ranks symptoms by number of days logged, descending', () {
    final logs = [
      log(DateTime(2026, 1, 1), encodeDayTags(flags: {'cramps', 'headache'})),
      log(DateTime(2026, 1, 2), encodeDayTags(flags: {'cramps'})),
      log(DateTime(2026, 1, 3), encodeDayTags(flags: {'cramps', 'acne'})),
    ];

    final a = SymptomAnalysisService.analyze(logs);

    expect(a.ranked.first.key, 'cramps');
    expect(a.ranked.first.dayCount, 3);
    expect(a.ranked.first.label, 'Cramps');
    // headache and acne each on one day.
    expect(a.ranked.firstWhere((s) => s.key == 'headache').dayCount, 1);
    expect(a.ranked.firstWhere((s) => s.key == 'acne').dayCount, 1);
    expect(a.hasData, isTrue);
  });

  test('pain severity is the average and peak of the 0-10 metric', () {
    final logs = [
      log(DateTime(2026, 1, 1), encodeDayTags(numbers: {kMetricPain: 4})),
      log(DateTime(2026, 1, 2), encodeDayTags(numbers: {kMetricPain: 8})),
    ];

    final a = SymptomAnalysisService.analyze(logs);
    expect(a.painAverage, closeTo(6.0, 0.001));
    expect(a.painPeak, 8);
  });

  test('excludes reserved keys (sex, cervical mucus) and empty logs', () {
    final logs = [
      log(DateTime(2026, 1, 1),
          encodeDayTags(flags: {'sex_protected', 'cm_dry', 'cramps'})),
      log(DateTime(2026, 1, 2), '{}'),
    ];

    final a = SymptomAnalysisService.analyze(logs);
    expect(a.ranked.map((s) => s.key), ['cramps']);
    expect(a.painAverage, isNull);
    expect(a.painPeak, isNull);
  });

  test('no symptoms at all -> hasData is false', () {
    expect(SymptomAnalysisService.analyze(const []).hasData, isFalse);
  });
}
