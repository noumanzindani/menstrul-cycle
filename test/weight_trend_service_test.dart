import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
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
}
