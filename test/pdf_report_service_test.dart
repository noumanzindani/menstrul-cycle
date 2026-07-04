import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/insights_service.dart';
import 'package:menstrul_track/services/pdf_report_service.dart';
import 'package:menstrul_track/services/prediction_service.dart';

DailyLog _log(DateTime date, {String symptoms = '{}', String? mood}) => DailyLog(
      id: 0,
      date: date,
      flow: FlowIntensity.medium,
      symptoms: symptoms,
      mood: mood,
      createdAt: date,
      updatedAt: date,
    );

void main() {
  test('symptomCounts tallies symptoms across logs and excludes sex keys', () {
    final logs = [
      _log(DateTime(2026, 1, 1),
          symptoms: encodeSymptoms({'cramps', 'headache'})),
      _log(DateTime(2026, 1, 2),
          symptoms: encodeSymptoms({'cramps', 'sex_protected'})),
    ];
    final counts = PdfReportService.symptomCounts(logs);
    expect(counts['cramps'], 2);
    expect(counts['headache'], 1);
    expect(counts.containsKey('sex_protected'), isFalse); // sex never in report
  });

  test('build returns a non-empty PDF including logs, prediction and mode',
      () async {
    final cycles = [
      Cycle(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 5), lengthDays: 28),
      Cycle(start: DateTime(2026, 1, 29), end: DateTime(2026, 2, 2), lengthDays: null),
    ];
    final bytes = await PdfReportService.build(
      insights: InsightsService.analyze(cycles),
      cycles: cycles,
      logs: [
        _log(DateTime(2026, 1, 1),
            symptoms: encodeSymptoms({'cramps'}), mood: 'calm'),
      ],
      prediction: PredictionService.predict(cycles, asOf: DateTime(2026, 1, 29)),
      mode: TrackingMode.conceive,
      generatedOn: DateTime(2026, 7, 4),
    );
    expect(bytes, isNotEmpty);
  });
}
