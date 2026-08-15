import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v4.dart';

/// v4 → v5 must ADD the sync tombstone table and `lastSyncedAt` without
/// disturbing existing rows. Seeds NON-DEFAULT values on purpose: asserting
/// defaults survive would also pass against a wipe-and-recreate migration.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not the migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v4 -> current adds sync bookkeeping and preserves existing data',
      () async {
    final schema = await verifier.schemaAt(4);

    final oldDb = DatabaseAtV4(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, weight_unit) '
      'VALUES (0, 30, 6, ?)',
      ['lb'],
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms) VALUES (?, ?)',
      [DateTime(2026, 3, 3).millisecondsSinceEpoch ~/ 1000, '{"cramps":true}'],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 30);
    expect(settings.defaultPeriodLength, 6);
    expect(settings.weightUnit, 'lb'); // v4 data untouched
    expect(settings.lastSyncedAt, isNull); // null => never synced => full pull
    expect(settings.settingsUpdatedAt, isNull); // null => never edited locally

    // The pre-existing log row survived the upgrade.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, '{"cramps":true}');

    // The new table exists and is empty.
    final tombstones = await db.select(db.syncTombstones).get();
    expect(tombstones, isEmpty);

    await db.close();
  });
}
