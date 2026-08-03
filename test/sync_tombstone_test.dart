import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  test('deleting a day records a tombstone so the deletion can be pushed',
      () async {
    final day = DateTime(2026, 5, 10);
    await repo.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');

    await repo.deleteForDate(day);

    expect(await repo.getForDate(day), isNull);
    final tombstones = await repo.getTombstones();
    expect(tombstones, hasLength(1));
    expect(tombstones.single.date, DateTime(2026, 5, 10));
  });

  test('deleting the same day twice keeps exactly one tombstone', () async {
    final day = DateTime(2026, 5, 11);
    await repo.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');

    await repo.deleteForDate(day);
    await repo.deleteForDate(day);

    expect(await repo.getTombstones(), hasLength(1));
  });

  test('clearTombstone removes it once the deletion has been pushed', () async {
    final day = DateTime(2026, 5, 12);
    await repo.upsert(date: day, flow: FlowIntensity.heavy, symptomsJson: '{}');
    await repo.deleteForDate(day);

    await repo.clearTombstone(day);

    expect(await repo.getTombstones(), isEmpty);
  });
}
