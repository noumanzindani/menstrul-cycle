import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

/// Custom reminders activate the dormant Reminders.title/recurrence columns and
/// ReminderType.custom. Unlike the three smart reminders there can be MANY, so
/// they use their own CRUD rather than the one-row-per-type `upsert`.
void main() {
  late AppDatabase db;
  late ReminderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReminderRepository(db);
  });
  tearDown(() => db.close());

  test('adds, lists, updates and deletes custom reminders', () async {
    final id = await repo.addCustom(title: 'Take vitamins', hour: 8, minute: 0);
    var custom = await repo.getCustom();
    expect(custom, hasLength(1));
    expect(custom.single.title, 'Take vitamins');
    expect(custom.single.type, ReminderType.custom);
    expect(custom.single.enabled, isTrue);

    await repo.updateCustom(
        id: id, title: 'Vitamins', hour: 9, minute: 30, enabled: false);
    custom = await repo.getCustom();
    expect(custom.single.title, 'Vitamins');
    expect(custom.single.hour, 9);
    expect(custom.single.enabled, isFalse);

    await repo.deleteCustom(id);
    expect(await repo.getCustom(), isEmpty);
  });

  test('custom reminders coexist with the one-per-type smart reminders', () async {
    await repo.upsert(
        type: ReminderType.logNudge, enabled: true, hour: 20, minute: 0);
    await repo.addCustom(title: 'A', hour: 8, minute: 0);
    await repo.addCustom(title: 'B', hour: 9, minute: 0);

    expect(await repo.getCustom(), hasLength(2));
    // The smart-reminder lookup still returns exactly one row.
    expect((await repo.getByType(ReminderType.logNudge))?.hour, 20);
  });
}
