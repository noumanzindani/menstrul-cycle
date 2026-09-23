import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v11.dart';

/// v11 → v12 must add `syncId` and `updatedAt` to `Reminders` and
/// `Medications` without disturbing existing rows.
///
/// Both tables became syncable in v12, and neither could be before: `id` is
/// `autoIncrement`, a LOCAL rowid, so device A's reminder 3 and device B's
/// reminder 3 are different reminders and syncing on it would merge unrelated
/// rows. Neither carried a timestamp either, so `decideMerge` had nothing to
/// compare.
///
/// Seeds NON-DEFAULT values on purpose: asserting defaults survive would also
/// pass against a wipe-and-recreate migration.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v11 -> v12 adds sync identity to reminders and medications, '
      'preserving existing rows', () async {
    final schema = await verifier.schemaAt(11);

    final oldDb = DatabaseAtV11(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings (id, default_cycle_length) VALUES (0, 29)',
    );
    await oldDb.customStatement(
      'INSERT INTO reminders (type, hour, minute, enabled, title) '
      'VALUES (?, ?, ?, ?, ?)',
      [0, 9, 30, 1, 'Log your day'],
    );
    // A product-change session, which rides a dormant reminders row's payload.
    // Seeded here so the migration is proven not to disturb it -- v12 makes
    // this table syncable, and THIS row is the one that must never travel.
    await oldDb.customStatement(
      'INSERT INTO reminders (type, hour, minute, enabled, payload) '
      'VALUES (?, ?, ?, ?, ?)',
      [4, 0, 0, 0, '{"startedAt":123456}'],
    );
    await oldDb.customStatement(
      'INSERT INTO medications (name, type, schedule, enabled) '
      'VALUES (?, ?, ?, ?)',
      ['Combined pill', 'pill', 'daily', 1],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 16);

    expect((await db.getSettings()).defaultCycleLength, 29);

    final reminders = await db.select(db.reminders).get();
    expect(reminders, hasLength(2));

    final nudge = reminders.firstWhere((r) => r.title == 'Log your day');
    expect(nudge.hour, 9);
    expect(nudge.minute, 30);
    expect(nudge.enabled, isTrue);
    expect(nudge.syncId, isNull,
        reason: 'the migration is additive and backfills nothing; the push '
            'assigns an id to any row still missing one');
    expect(nudge.updatedAt, isNull,
        reason: 'a row this device cannot date must lose to a remote copy, '
            'which null is');

    final session = reminders.firstWhere((r) => r.payload != null);
    expect(session.payload, '{"startedAt":123456}',
        reason: 'the live product-change session was disturbed by a migration '
            'that only claims to add two columns');

    final meds = await db.select(db.medications).get();
    expect(meds, hasLength(1));
    expect(meds.single.name, 'Combined pill');
    expect(meds.single.schedule, 'daily');
    expect(meds.single.syncId, isNull);
    expect(meds.single.updatedAt, isNull);

    // Usable post-migration, not merely present.
    final now = DateTime(2026, 9, 18, 6);
    await (db.update(db.reminders)..where((r) => r.id.equals(nudge.id)))
        .write(RemindersCompanion(
      syncId: const Value('rem-uuid-1'),
      updatedAt: Value(now),
    ));
    final updated = await (db.select(db.reminders)
          ..where((r) => r.id.equals(nudge.id)))
        .getSingle();
    expect(updated.syncId, 'rem-uuid-1');
    expect(updated.updatedAt, now);
    expect(updated.title, 'Log your day',
        reason: 'writing the new columns rewrote the old ones');

    await db.close();
  });
}
