import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v6.dart';

/// v6 → v7 must ADD the three photo-description columns without disturbing
/// existing rows. Seeds NON-DEFAULT values on purpose: asserting defaults
/// survive would also pass against a wipe-and-recreate migration.
///
/// This is the first migration test to seed a `media_items` row. That table
/// arrived in v6 and nothing has yet proven it survives a later upgrade — and a
/// media row is the ONLY local record that an uploaded photo exists, so losing
/// one strands the bytes in Cloud Storage where the orphan sweep will delete
/// them. That is silent, permanent loss of the user's own photographs.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not the migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v6 -> v7 adds the analysis columns and preserves existing data',
      () async {
    final schema = await verifier.schemaAt(6);

    final oldDb = DatabaseAtV6(schema.newConnection());
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
    await oldDb.customStatement(
      'INSERT INTO media_items '
      '(id, uid, kind, storage_path, thumb_path, bytes, captured_at, '
      'created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'media-1',
        'uid-abc',
        'image',
        'users/uid-abc/media/media-1/original.jpg',
        'users/uid-abc/media/media-1/thumb.jpg',
        123456,
        DateTime(2026, 7, 7).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 7, 8).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 7, 9).millisecondsSinceEpoch ~/ 1000,
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

    // The new columns exist and read as "never opted in, never used", which is
    // the only correct default: an upgrade must not opt an existing user in.
    expect(settings.analysisConsentUid, isNull);
    expect(settings.analysisCountDay, isNull);
    expect(settings.analysisCountToday, isNull);

    // The pre-existing log row survived, blob and free text included.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, '{"cramps":true,"weight":61.5}');
    expect(logs.single.notes, 'a note that must survive');

    // The unpushed deletion intent survived. Losing it resurrects the day.
    final tombstones = await db.select(db.syncTombstones).get();
    expect(tombstones, hasLength(1));
    expect(tombstones.single.date, DateTime(2026, 2, 2));

    // The media row survived. Losing it strands the bytes for the orphan sweep.
    final media = await db.select(db.mediaItems).get();
    expect(media, hasLength(1));
    expect(media.single.id, 'media-1');
    expect(media.single.uid, 'uid-abc');
    expect(
      media.single.storagePath,
      'users/uid-abc/media/media-1/original.jpg',
    );
    expect(media.single.bytes, 123456);

    await db.close();
  });
}
