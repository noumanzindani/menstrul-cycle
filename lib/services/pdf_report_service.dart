import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../common/catalog.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../models/insights.dart';
import '../models/prediction.dart';
import 'bmi_service.dart';
import 'insights_narrator.dart';
import 'weight_trend_service.dart';

/// Builds a printable/shareable "for your doctor" PDF from the user's history.
/// Everything is generated on-device from local data.
class PdfReportService {
  const PdfReportService._();

  /// The label for [key] in [options], or null when it is absent or unknown to
  /// this build.
  ///
  /// Deliberately NOT the same contract as [_labelFor] below, which falls back
  /// to the raw key. That fallback is right for symptom rows — every key there
  /// comes from this build's own catalog — and wrong here, where a key may have
  /// been written by a NEWER build and `dx_from_the_future` in a clinical
  /// summary is worse than an omitted line.
  static String? _knownLabel(List<TrackOption> options, String? key) {
    if (key == null) return null;
    for (final o in options) {
      if (o.key == key) return o.label;
    }
    return null;
  }

  static Future<Uint8List> build({
    required Insights insights,
    required List<Cycle> cycles,
    required DateTime generatedOn,
    List<DailyLog> logs = const [],
    PredictionResult? prediction,
    TrackingMode? mode,
    DateTime? dateOfBirth,
    double? heightCm,
    double? profileWeightKg,
    int? menarcheAge,
    String? contraceptionMethod,
    DateTime? contraceptionStartDate,
    Set<String> knownDiagnoses = const {},
    bool? breastfeeding,
    DateTime? breastfeedingSince,
  }) async {
    final doc = pw.Document();
    final stats = insights.stats;
    final df = DateFormat.yMMMd();

    String orDash(Object? v) => v?.toString() ?? '—';
    String date(DateTime? d) => d == null ? '-' : df.format(d);

    // Most recent cycles first, capped for a tidy one-pager.
    final recent = cycles.reversed.take(12).toList();

    // The profile header a clinician reads first. Every line is omitted when
    // its field was never answered, and the whole block disappears when none of
    // them were — a user who skipped every question gets the report they always
    // got, not an empty heading.
    //
    // METRIC ALWAYS, never the user's display preference: the same rule the
    // weight trend below already follows, for the same reason — this document
    // is read by someone else.
    //
    // The weight here is the PROFILE field, deliberately NOT the per-day
    // `kMetricWeight` that drives the trend section below. They are two
    // different questions: "what do you weigh now" versus "how has it moved
    // over 90 days". Never make one read from the other.
    final age = ageInYears(dateOfBirth, on: generatedOn);
    // Resolved to LABELS, never printed as raw keys. A key this build does not
    // recognise (written by a newer one) resolves to null and is dropped: a
    // clinician reading `dx_from_the_future` in a summary is worse served than
    // by an omission.
    final contraceptionLabel =
        _knownLabel(kContraceptionOptions, contraceptionMethod);
    final diagnosisLabels = [
      for (final o in kDiagnosisOptions)
        if (knownDiagnoses.contains(o.key)) o.label,
    ];
    final profileRows = <List<String>>[
      if (age != null) ['Age', '$age years'],
      if (heightCm != null)
        ['Height', '${formatHeightFromCm(heightCm, kWeightUnitKg)} cm'],
      if (profileWeightKg != null)
        [
          'Current weight',
          '${formatWeightFromKg(profileWeightKg, kWeightUnitKg)} kg',
        ],
      if (menarcheAge != null) ['Age at first period', '$menarcheAge years'],
      // The clinical context. Placed after the body measurements because that
      // is the order a clinician reads them in, and because each of these
      // changes what the cycle numbers further down MEAN: hormonal
      // contraception, a known diagnosis and lactation each redefine a normal
      // cycle.
      //
      // Every row is omitted when the question was never answered. A report
      // that printed "Breastfeeding: No" for somebody who was never asked would
      // be inventing a clinical fact, which is worse than an absent line.
      if (contraceptionLabel != null)
        [
          'Contraception',
          contraceptionStartDate == null
              ? contraceptionLabel
              : '$contraceptionLabel (since ${df.format(contraceptionStartDate)})',
        ],
      if (diagnosisLabels.isNotEmpty)
        ['Known diagnoses', diagnosisLabels.join(', ')],
      if (breastfeeding != null)
        [
          'Breastfeeding',
          if (breastfeeding && breastfeedingSince != null)
            'Yes (since ${df.format(breastfeedingSince)})'
          else
            breastfeeding ? 'Yes' : 'No',
        ],
    ];
    // Read out verbatim, never reassembled here: `bmi_service.dart` is the one
    // file in `lib/` permitted to carry body-judgement copy, and a structural
    // test fails the build on a band word or a `BMI ` prefix written anywhere
    // else. It returns null unless both inputs are present and plausible.
    final bmi = BmiService.bmiReadout(
      heightCm: heightCm,
      weightKg: profileWeightKg,
    );

    // Weight is reported in kg regardless of the display preference — this is a
    // clinical document.
    final weight = WeightTrendService.compute(logs, asOf: generatedOn);

    // Symptom & mood frequency across logged days. Sex activity is deliberately
    // excluded (decodeSymptoms drops sex_ keys) — it never belongs in a doctor
    // report that gets printed/emailed.
    final symCounts = symptomCounts(logs);
    final moodCounts = _moodCounts(logs);
    final symRows = symCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final moodRows = moodCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hasFertility = prediction != null && prediction.hasPrediction;
    // Plain-language cycle patterns for the clinician (no "current phase" line —
    // a doctor summary describes history, not a transient state).
    final narratives = InsightsNarrator.narrate(cycles: cycles, logs: logs);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(),
        ),
        build: (context) => [
          pw.Text('LunaTrack — Cycle Summary',
              style:
                  pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Generated ${df.format(generatedOn)}',
              style: const pw.TextStyle(color: PdfColors.grey700)),
          if (mode != null)
            pw.Text('Tracking focus: ${_modeLabel(mode)}',
                style: const pw.TextStyle(color: PdfColors.grey700)),
          pw.Divider(),
          if (profileRows.isNotEmpty || bmi != null) ...[
            pw.SizedBox(height: 8),
            pw.Text('Profile',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              border: null,
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              headers: const ['Detail', 'Value'],
              data: profileRows,
            ),
            if (bmi != null) ...[
              pw.SizedBox(height: 6),
              pw.Text(bmi),
            ],
            pw.SizedBox(height: 8),
          ],
          pw.SizedBox(height: 8),
          pw.Text('Summary',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            border: null,
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: const ['Metric', 'Value'],
            data: [
              ['Cycles tracked', '${stats.cyclesTracked}'],
              ['Average cycle length', '${orDash(stats.averageCycleLength)} days'],
              ['Cycle range',
                  '${orDash(stats.shortestCycle)}–${orDash(stats.longestCycle)} days'],
              ['Cycle variability (std dev)',
                  '${stats.variability.toStringAsFixed(1)} days'],
              ['Average period length',
                  '${orDash(stats.averagePeriodLength)} days'],
              ['Longest period', '${orDash(stats.longestPeriod)} days'],
              ['Days since last period', orDash(stats.daysSinceLastPeriod)],
            ],
          ),
          if (narratives.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Cycle patterns',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            for (final n in narratives) pw.Bullet(text: n.text),
          ],
          pw.SizedBox(height: 16),
          pw.Text('Recent cycles',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: const ['Period start', 'Cycle length', 'Period length'],
            data: [
              for (final c in recent)
                [
                  df.format(c.start),
                  c.lengthDays != null ? '${c.lengthDays} days' : '—',
                  '${c.periodLengthDays} days',
                ],
            ],
          ),
          if (weight != null) ...[
            pw.SizedBox(height: 16),
            pw.Text('Weight',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              headers: const ['Readings', 'Latest', 'Change'],
              data: [
                [
                  '${weight.points.length}',
                  '${weight.points.last.kg.toStringAsFixed(1)} kg',
                  '${weight.netChangeKg >= 0 ? '+' : ''}'
                      '${weight.netChangeKg.toStringAsFixed(1)} kg',
                ],
              ],
            ),
          ],
          if (hasFertility) ...[
            pw.SizedBox(height: 16),
            pw.Text('Estimated fertility (calendar method)',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(
              'Next period ~${date(prediction.nextPeriodStart)}; '
              'estimated ovulation ~${date(prediction.ovulationDay)}; '
              'fertile window ${date(prediction.fertileWindowStart)}'
              ' to ${date(prediction.fertileWindowEnd)}.',
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Estimates from cycle history — not confirmed by ovulation testing.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
          if (symRows.isNotEmpty || moodRows.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Symptom & mood frequency',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              headers: const ['Logged', 'Days'],
              data: [
                for (final e in symRows)
                  [symptomLabel(e.key), '${e.value}'],
                for (final e in moodRows)
                  ['Mood: ${_labelFor(kMoodOptions, e.key)}', '${e.value}'],
              ],
            ),
          ],
          if (insights.flags.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes to discuss',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            for (final f in insights.flags)
              pw.Bullet(text: '${f.title}: ${f.message}'),
          ],
          pw.SizedBox(height: 24),
          pw.Divider(),
          pw.Text(
            'This summary was generated by LunaTrack from self-reported data. '
            'Predictions and statistics are estimates, are not a contraceptive '
            'method, and are not a medical diagnosis.',
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Whole years between [dateOfBirth] and [on], or null when there is no
  /// honest number to print.
  ///
  /// [on] is the report's `generatedOn` rather than the clock: the age in a
  /// doctor report is the age on the day it was produced, and injecting it is
  /// also what keeps the output byte-deterministic for the size-based tests.
  ///
  /// A birth date after [on] returns null instead of a negative number — an
  /// impossible answer is omitted, not rendered. A birthday that has not yet
  /// come round in [on]'s year counts one year fewer, which puts a Feb 29 birth
  /// date's birthday on March 1 in a non-leap year.
  static int? ageInYears(DateTime? dateOfBirth, {required DateTime on}) {
    if (dateOfBirth == null) return null;
    var years = on.year - dateOfBirth.year;
    final beforeBirthday = on.month < dateOfBirth.month ||
        (on.month == dateOfBirth.month && on.day < dateOfBirth.day);
    if (beforeBirthday) years--;
    return years < 0 ? null : years;
  }

  /// Counts how many logged days include each symptom. Sex keys are excluded
  /// because [decodeSymptoms] drops the `sex_` namespace.
  static Map<String, int> symptomCounts(List<DailyLog> logs) {
    final counts = <String, int>{};
    for (final log in logs) {
      for (final key in decodeSymptoms(log.symptoms)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return counts;
  }

  static Map<String, int> _moodCounts(List<DailyLog> logs) {
    final counts = <String, int>{};
    for (final log in logs) {
      final m = log.mood;
      if (m != null && m.isNotEmpty) counts[m] = (counts[m] ?? 0) + 1;
    }
    return counts;
  }

  static String _labelFor(List<TrackOption> options, String key) => options
      .firstWhere((o) => o.key == key, orElse: () => TrackOption(key, key))
      .label;

  static String _modeLabel(TrackingMode mode) => switch (mode) {
        TrackingMode.track => 'Cycle tracking',
        TrackingMode.conceive => 'Trying to conceive',
        TrackingMode.perimenopause => 'Perimenopause',
        TrackingMode.pregnancy => 'Pregnancy',
      };
}
