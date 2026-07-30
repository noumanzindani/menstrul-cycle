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

    test('GUARDRAIL: no body-judgement copy ships in any user-facing string',
        () async {
      // Weight is DESCRIPTIVE only. A classification ("healthy", "obese",
      // "normal range") or a derived BMI is a judgeable body label — the same
      // class of harm as a synthesized fertility percentage, and the reason this
      // feature has no height field to compute one from.
      //
      // Scoped to single-quoted Dart string literals with word boundaries: a
      // bare /bmi/ search matches "su(bmi)t", and an unscoped one flags the
      // comments that forbid these very words, so it would fire forever on a
      // clean tree and train everyone to ignore it.
      final forbidden = RegExp(
        r"'[^']*\b(BMI|body mass|overweight|obese|underweight|"
        r"ideal weight|healthy weight|normal range)\b[^']*'",
        caseSensitive: false,
      );
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (forbidden.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: 'body-judgement copy found');
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
