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

  /// The clinician profile header: age, height, current weight, age at first
  /// period and the BMI readout.
  ///
  /// Content is asserted by output SIZE, never by substring — the `pdf`
  /// package writes text into compressed streams, so a byte search finds
  /// nothing even for headings that ARE present. `generatedOn` is injected
  /// rather than read from the clock, which is what makes the output
  /// byte-deterministic and size a real content probe. (The age arithmetic is
  /// tested directly against the pure helper instead, because "the document
  /// grew" cannot tell 41 from 42.)
  group('profile header', () {
    final on = DateTime(2026, 7, 4);

    Future<int> pdfSize({
      DateTime? dateOfBirth,
      double? heightCm,
      double? profileWeightKg,
      int? menarcheAge,
      List<DailyLog> logs = const [],
    }) async {
      final bytes = await PdfReportService.build(
        insights: InsightsService.analyze(const []),
        cycles: const [],
        logs: logs,
        generatedOn: on,
        dateOfBirth: dateOfBirth,
        heightCm: heightCm,
        profileWeightKg: profileWeightKg,
        menarcheAge: menarcheAge,
      );
      return bytes.length;
    }

    test('age is counted from the date of birth as of the generation date', () {
      // Birthday already passed in the generation year.
      expect(
          PdfReportService.ageInYears(DateTime(1990, 3, 2), on: on), 36);
      // Birthday still ahead in the generation year — one year fewer.
      expect(
          PdfReportService.ageInYears(DateTime(1990, 11, 2), on: on), 35);
      // Birthday is the generation day itself.
      expect(
          PdfReportService.ageInYears(DateTime(1990, 7, 4), on: on), 36);
      // The day before the birthday.
      expect(
          PdfReportService.ageInYears(DateTime(1990, 7, 5), on: on), 35);
    });

    test('a leap-day birth date ages on March 1 in a non-leap year', () {
      expect(
          PdfReportService.ageInYears(DateTime(2000, 2, 29),
              on: DateTime(2026, 2, 28)),
          25);
      expect(
          PdfReportService.ageInYears(DateTime(2000, 2, 29),
              on: DateTime(2026, 3, 1)),
          26);
    });

    test('no date of birth, or one in the future, yields no age', () {
      expect(PdfReportService.ageInYears(null, on: on), isNull);
      expect(
          PdfReportService.ageInYears(DateTime(2026, 7, 5), on: on), isNull);
    });

    test('a user who answered nothing gets exactly the report they get today',
        () async {
      final withoutArgs = await pdfSize();
      final allNull = await pdfSize(
        dateOfBirth: null,
        heightCm: null,
        profileWeightKg: null,
        menarcheAge: null,
      );
      // Identical size == the whole block, heading included, was never built.
      expect(allNull, withoutArgs);
    });

    test('each profile field that is answered lands in the document', () async {
      final baseline = await pdfSize();
      expect(await pdfSize(dateOfBirth: DateTime(1990, 3, 2)),
          greaterThan(baseline));
      expect(await pdfSize(heightCm: 165.0), greaterThan(baseline));
      expect(await pdfSize(profileWeightKg: 62.0), greaterThan(baseline));
      expect(await pdfSize(menarcheAge: 13), greaterThan(baseline));
    });

    test('the BMI readout appears only when height and weight are both usable',
        () async {
      // Same field count and same string lengths in both documents; the only
      // difference is that 10.0 kg is outside BmiService's plausible range, so
      // the readout is suppressed while both rows still render.
      final withReadout = await pdfSize(heightCm: 165.0, profileWeightKg: 62.0);
      final withoutReadout =
          await pdfSize(heightCm: 165.0, profileWeightKg: 10.0);
      expect(withReadout, greaterThan(withoutReadout));

      // Same again on the other input: 500.0 is outside the plausible height
      // range and is the same number of characters as 165.0, so the only thing
      // the size can be reporting is the missing readout.
      final implausibleHeight =
          await pdfSize(heightCm: 500.0, profileWeightKg: 62.0);
      expect(withReadout, greaterThan(implausibleHeight));

      // One input alone can never produce a readout.
      final heightOnly = await pdfSize(heightCm: 165.0);
      final weightOnly = await pdfSize(profileWeightKg: 62.0);
      expect(withReadout, greaterThan(heightOnly));
      expect(withReadout, greaterThan(weightOnly));
    });

    test('the weight trend section still comes from the daily metric, not the '
        'profile field', () async {
      DailyLog weighed(DateTime date, double kg) => DailyLog(
            id: 0,
            date: date,
            flow: null,
            symptoms: encodeDayTags(numbers: {kMetricWeight: kg}),
            createdAt: date,
            updatedAt: date,
          );
      const profileKg = 62.0;
      // Two daily readings are the minimum WeightTrendService will chart.
      final withDailyReadings = await pdfSize(
        profileWeightKg: profileKg,
        logs: [
          weighed(DateTime(2026, 6, 10), 63.0),
          weighed(DateTime(2026, 6, 20), 62.0),
        ],
      );
      final profileOnly = await pdfSize(profileWeightKg: profileKg);
      expect(withDailyReadings, greaterThan(profileOnly));
    });
  });
}
