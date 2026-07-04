import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

void main() {
  late AppDatabase db;
  late ReminderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReminderRepository(db);
  });
  tearDown(() => db.close());

  test('upsert inserts then updates a single row per type', () async {
    await repo.upsert(
      type: ReminderType.periodSoon,
      enabled: true,
      hour: 9,
      minute: 30,
      payload: '{"daysBefore":2}',
    );
    var row = await repo.getByType(ReminderType.periodSoon);
    expect(row, isNotNull);
    expect(row!.type, ReminderType.periodSoon); // enum round-trips
    expect(row.enabled, isTrue);
    expect(row.hour, 9);
    expect(row.payload, '{"daysBefore":2}');

    await repo.upsert(
      type: ReminderType.periodSoon,
      enabled: false,
      hour: 8,
      minute: 0,
      payload: '{"daysBefore":3}',
    );
    final all = await repo.getAll();
    expect(all, hasLength(1)); // updated, not duplicated
    row = all.first;
    expect(row.enabled, isFalse);
    expect(row.hour, 8);
    expect(row.payload, '{"daysBefore":3}');
  });

  test('different types coexist', () async {
    await repo.upsert(
        type: ReminderType.logNudge, enabled: true, hour: 20, minute: 0);
    await repo.upsert(
        type: ReminderType.fertileWindow, enabled: true, hour: 9, minute: 0);
    final all = await repo.getAll();
    expect(all, hasLength(2));
  });
}
