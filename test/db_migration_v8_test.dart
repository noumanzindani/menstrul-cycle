import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v7.dart';

/// v7 → current must ADD the four profile columns (date of birth, height, profile
/// weight, menarche age) without disturbing existing rows. Seeds NON-DEFAULT
/// values on purpose: asserting defaults survive would also pass against a
/// wipe-and-recreate migration.
///
/// The four new columns must read NULL after the upgrade. That is the only
/// correct answer: an existing user has never been asked for any of them, and a
/// fabricated height or date of birth would feed the BMI readout and the doctor
/// PDF header with a number the user never gave.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not the migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v7 -> current adds the profile columns and preserves existing data',
      () async {
    final schema = await verifier.schemaAt(7);

    final oldDb = DatabaseAtV7(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, weight_unit, '
      'last_synced_at, settings_updated_at, analysis_consent_uid, '
      'analysis_count_day, analysis_count_today) '
      'VALUES (0, 31, 7, ?, ?, ?, ?, ?, ?)',
      [
        'lb',
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 8, 2).millisecondsSinceEpoch ~/ 1000,
        'uid-abc',
        '2026-08-12',
        3,
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
    await verifier.migrateAndValidate(db, 10);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.weightUnit, 'lb'); // v4 data untouched
    expect(settings.lastSyncedAt, DateTime(2026, 8, 1)); // v5 data untouched
    expect(settings.settingsUpdatedAt, DateTime(2026, 8, 2));
    expect(settings.analysisConsentUid, 'uid-abc'); // v7 data untouched
    expect(settings.analysisCountDay, '2026-08-12');
    expect(settings.analysisCountToday, 3);

    // The new columns exist and read as "never answered", which is the only
    // correct default: the upgrade must not invent a body measurement or a
    // date of birth for a user who was never asked for one.
    expect(settings.dateOfBirth, isNull);
    expect(settings.heightCm, isNull);
    expect(settings.profileWeightKg, isNull);
    expect(settings.menarcheAge, isNull);

    // The pre-existing log row survived, blob and free text included. The
    // per-day `weight` metric in that blob is a SEPARATE field from the new
    // profile weight and must stay exactly where it is.
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
