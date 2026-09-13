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
      String? contraceptionMethod,
      DateTime? contraceptionStartDate,
      Set<String> knownDiagnoses = const {},
      bool? breastfeeding,
      DateTime? breastfeedingSince,
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
        contraceptionMethod: contraceptionMethod,
        contraceptionStartDate: contraceptionStartDate,
        knownDiagnoses: knownDiagnoses,
        breastfeeding: breastfeeding,
        breastfeedingSince: breastfeedingSince,
      );
      return bytes.length;
    }

    /// The clinical profile, which a clinician needs BEFORE reading a single
    /// cycle number: hormonal contraception, a known diagnosis and lactation
    /// each change what a normal cycle even looks like.
    ///
    /// Size probes, for the same reason as the rest of this group — the `pdf`
    /// package compresses its text streams, so a substring search finds
    /// nothing even for content that is definitely there.
    group('clinical context', () {
      test('an answered contraception method adds a row', () async {
        final without = await pdfSize();
        final with_ = await pdfSize(contraceptionMethod: 'contra_implant');
        expect(with_, greaterThan(without));
      });

      test('a start date adds to that row rather than replacing it', () async {
        final methodOnly = await pdfSize(contraceptionMethod: 'contra_ring');
        final withDate = await pdfSize(
          contraceptionMethod: 'contra_ring',
          contraceptionStartDate: DateTime(2024, 6, 1),
        );
        expect(withDate, greaterThan(methodOnly));
      });

      test('a start date with NO method is not printed on its own', () async {
        // A date belonging to a method that was never recorded would be a
        // clinical fact attached to nothing.
        expect(
          await pdfSize(contraceptionStartDate: DateTime(2024, 6, 1)),
          await pdfSize(),
        );
      });

      test('diagnoses are printed, and an empty set is not', () async {
        final none = await pdfSize();
        expect(await pdfSize(knownDiagnoses: const {}), none);
        expect(await pdfSize(knownDiagnoses: const {'dx_pcos'}),
            greaterThan(none));
      });

      test('an unrecognised diagnosis key is dropped, not printed raw',
          () async {
        // Written by a newer build. Printing `dx_from_the_future` into a
        // document a clinician reads is worse than omitting it.
        expect(
          await pdfSize(knownDiagnoses: const {'dx_from_the_future'}),
          await pdfSize(),
        );
      });

      test('breastfeeding prints yes and no, but never on "not asked"',
          () async {
        final notAsked = await pdfSize();
        expect(await pdfSize(breastfeeding: null), notAsked,
            reason: 'a report must not answer a question nobody asked');
        expect(await pdfSize(breastfeeding: false), greaterThan(notAsked));
        expect(await pdfSize(breastfeeding: true), greaterThan(notAsked));
      });

      test('a since-date only prints alongside a yes', () async {
        final yes = await pdfSize(breastfeeding: true);
        expect(
          await pdfSize(
              breastfeeding: false, breastfeedingSince: DateTime(2025, 9, 9)),
          lessThan(yes + 40),
        );
        expect(
          await pdfSize(
              breastfeeding: true, breastfeedingSince: DateTime(2025, 9, 9)),
          greaterThan(yes),
        );
      });
    });

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
