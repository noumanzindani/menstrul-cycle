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

  test(
      'deleteAllData drops pending tombstones, so they cannot be pushed under '
      'whichever account signs in next on this device', () async {
    final day = DateTime(2026, 5, 13);
    await repo.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');
    await repo.deleteForDate(day);
    expect(await repo.getTombstones(), hasLength(1));

    await db.deleteAllData();

    // A tombstone is a not-yet-pushed "delete this day" intent. Surviving a
    // full local wipe, it would be pushed into the NEXT account's own
    // `users/{uid}/deletions` — a deletion marker for a day that account
    // never tracked. See the trade-off recorded on `deleteAllData` itself.
    expect(await repo.getTombstones(), isEmpty);
  });
}
