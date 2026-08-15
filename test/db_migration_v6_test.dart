import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v5.dart';

/// v5 → v6 must ADD the `media_items` table without disturbing existing rows.
/// Seeds NON-DEFAULT values on purpose: asserting defaults survive would also
/// pass against a wipe-and-recreate migration.
///
/// This is the first migration test to seed a `sync_tombstones` row. That table
/// arrived in v5 and nothing has yet proven it survives a later upgrade — a
/// tombstone is an unpushed deletion intent, so losing one silently resurrects
/// a day the user deleted the next time sync runs.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not the migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v5 -> v6 adds media_items and preserves existing data', () async {
    final schema = await verifier.schemaAt(5);

    final oldDb = DatabaseAtV5(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, weight_unit, '
      'last_synced_at, settings_updated_at) '
      'VALUES (0, 31, 7, ?, ?, ?)',
      [
        'lb',
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 8, 2).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms, notes) VALUES (?, ?, ?)',
      [
        DateTime(2026, 3, 3).millisecondsSinceEpoch ~/ 1000,
        '{"cramps":true,"weight":61.5}',
        'a note that must survive',
      ],
    );
    await oldDb.customStatement(
      'INSERT INTO sync_tombstones (date, deleted_at) VALUES (?, ?)',
      [
        DateTime(2026, 2, 2).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 2, 3).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.weightUnit, 'lb'); // v4 data untouched
    expect(settings.lastSyncedAt, DateTime(2026, 8, 1)); // v5 data untouched
    expect(settings.settingsUpdatedAt, DateTime(2026, 8, 2));

    // The pre-existing log row survived, blob and free text included.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, '{"cramps":true,"weight":61.5}');
    expect(logs.single.notes, 'a note that must survive');

    // The unpushed deletion intent survived. Losing it resurrects the day.
    final tombstones = await db.select(db.syncTombstones).get();
    expect(tombstones, hasLength(1));
    expect(tombstones.single.date, DateTime(2026, 2, 2));

    // The new table exists and is empty.
    final media = await db.select(db.mediaItems).get();
    expect(media, isEmpty);

    await db.close();
  });
}
