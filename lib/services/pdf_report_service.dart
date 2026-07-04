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

/// Builds a printable/shareable "for your doctor" PDF from the user's history.
/// Everything is generated on-device from local data.
class PdfReportService {
  const PdfReportService._();

  static Future<Uint8List> build({
    required Insights insights,
    required List<Cycle> cycles,
    required DateTime generatedOn,
    List<DailyLog> logs = const [],
    PredictionResult? prediction,
    TrackingMode? mode,
  }) async {
    final doc = pw.Document();
    final stats = insights.stats;
    final df = DateFormat.yMMMd();

    String orDash(Object? v) => v?.toString() ?? '—';
    String date(DateTime? d) => d == null ? '-' : df.format(d);

    // Most recent cycles first, capped for a tidy one-pager.
    final recent = cycles.reversed.take(12).toList();

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
                  [_labelFor(kSymptomOptions, e.key), '${e.value}'],
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
      };
}
