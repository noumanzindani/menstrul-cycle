import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/insights_service.dart';
import 'package:menstrul_track/services/pdf_report_service.dart';
import 'package:menstrul_track/services/weight_trend_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  final asOf = DateTime(2026, 6, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seed(DateTime date, {double? kg}) => repo.upsert(
        date: date,
        flow: null,
        symptomsJson: encodeDayTags(
          numbers: {kMetricWeight: ?kg},
        ),
      );

  test('returns null with fewer than two readings', () async {
    await seed(DateTime(2026, 5, 30), kg: 62.0);
    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf);
    expect(trend, isNull);
  });

  test('orders points chronologically and computes net change', () async {
    await seed(DateTime(2026, 5, 30), kg: 61.0);
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 20), kg: 62.0);

    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf)!;

    expect(trend.points.map((p) => p.kg).toList(), [63.0, 62.0, 61.0]);
    expect(trend.netChangeKg, closeTo(-2.0, 0.001));
  });

  test('ignores days with no weight logged', () async {
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 15)); // symptoms only, no weight
    await seed(DateTime(2026, 5, 20), kg: 62.0);

    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf)!;
    expect(trend.points, hasLength(2));
  });

  test('excludes readings older than the window', () async {
    await seed(DateTime(2026, 1, 1), kg: 70.0); // >90 days before asOf
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 20), kg: 62.0);

    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf)!;
    expect(trend.points, hasLength(2));
    expect(trend.points.first.kg, 63.0);
  });

  /// The doctor PDF must carry weight but NEVER the user's free-text notes.
  ///
  /// Asserted by output SIZE, not by substring. The `pdf` package writes text
  /// into compressed streams, so a byte search finds nothing even for headings
  /// that are definitely present — meaning "note text not found" would prove
  /// nothing at all. `generatedOn` is injected rather than read from the clock,
  /// so the output is byte-deterministic and size becomes a real content probe.
  group('doctor PDF', () {
    Future<int> pdfSize({String? note, bool withWeight = false}) async {
      final scratch = AppDatabase.forTesting(NativeDatabase.memory());
      final r = DailyLogRepository(scratch);
      if (withWeight) {
        await r.upsert(
          date: DateTime(2026, 5, 10),
          flow: null,
          symptomsJson: encodeDayTags(numbers: {kMetricWeight: 63.0}),
        );
        await r.upsert(
          date: DateTime(2026, 5, 20),
          flow: null,
          symptomsJson: encodeDayTags(numbers: {kMetricWeight: 62.0}),
        );
      }
      await r.upsert(
        date: DateTime(2026, 5, 21),
        flow: null,
        symptomsJson: encodeDayTags(),
        notes: note,
      );
      final bytes = await PdfReportService.build(
        insights: InsightsService.analyze(const []),
        cycles: const [],
        generatedOn: DateTime(2026, 6, 1),
        logs: await r.getAll(),
      );
      await scratch.close();
      return bytes.length;
    }

    test('GUARDRAIL: notes text never reaches the report', () async {
      final without = await pdfSize();
      final withLongNote = await pdfSize(note: 'private therapy notes ' * 200);
      // A ~4KB note cannot be rendered into the document without changing its
      // compressed size. Identical size == the text was never included.
      expect(withLongNote, without);
    });

    /// GUARDRAIL: body-judgement copy is confined to ONE owning module.
    ///
    /// The original ruling was absolute — no BMI, no height, no classification
    /// of any kind — on the grounds that a judgeable body label is the same
    /// class of harm as a synthesized fertility percentage. The project owner
    /// DELIBERATELY REVERSED that ruling on 2026-09-13, for one feature: a
    /// height and a date of birth are now collected on the profile, and
    /// Insights shows a BMI readout with a WHO band label.
    ///
    /// The reversal is SCOPED, and this scan is what scopes it.
    /// `lib/services/bmi_service.dart` is the single exemption; every other
    /// file under `lib/` is still held to the original ruling. That is the
    /// entire point of keeping the test rather than deleting it: the exemption
    /// is what stops "overweight", "obese" or a stray `BMI ` prefix leaking
    /// into Insights prose, the day-entry form, a notification, the doctor PDF
    /// or a settings subtitle by accident — diffs where nobody would think to
    /// re-ask the question. The UI reads these strings out of `BmiService`
    /// instead of writing its own. A new offender here is a question about
    /// whether the owner widened the reversal, NOT an invitation to add a
    /// second exemption.
    ///
    /// Scoped to single-quoted Dart string literals with word boundaries: a
    /// bare /bmi/ search matches "su(bmi)t", and an unscoped one flags the
    /// comments that discuss these very words, so it would fire forever on a
    /// clean tree and train everyone to ignore it.
    test('GUARDRAIL: body-judgement copy stays inside bmi_service.dart',
        () async {
      const exempt = 'lib/services/bmi_service.dart';
      final forbidden = RegExp(
        r"'[^']*\b(BMI|body mass|overweight|obese|underweight|"
        r"ideal weight|healthy weight|normal range)\b[^']*'",
        caseSensitive: false,
      );
      final offenders = <String>[];
      var exemptWasScanned = false;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.replaceAll(r'\', '/') == exempt) {
          exemptWasScanned = true;
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (forbidden.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'body-judgement copy found outside $exempt — the 2026-09-13 '
              'reversal covers that file ONLY. Read these strings out of '
              'BmiService instead of writing new ones.');

      // The exemption has to stay LIVE and stay EARNED. If bmi_service.dart is
      // renamed or deleted, the path above quietly exempts nothing and this
      // test would keep passing while guarding a file that no longer exists —
      // the "guardrail nobody re-armed" failure this project keeps finding.
      expect(exemptWasScanned, isTrue,
          reason: '$exempt no longer exists; re-point or drop the exemption.');
      expect(File(exempt).readAsLinesSync().any(forbidden.hasMatch), isTrue,
          reason: '$exempt carries no body-judgement copy any more. If the '
              'owner re-tightened the ruling, delete the exemption too.');
    });

    test('includes weight when there is a trend', () async {
      final without = await pdfSize();
      final withWeight = await pdfSize(withWeight: true);
      // The positive half: proves the size probe above can actually detect
      // added content, so the guardrail is not vacuous.
      expect(withWeight, greaterThan(without));
    });
  });
}
