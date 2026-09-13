import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v8.dart';

/// v8 → v9 must ADD the five clinical-profile columns (contraception method and
/// start date, known diagnoses, breastfeeding and since-date) without
/// disturbing existing rows. Seeds NON-DEFAULT values on purpose: asserting
/// defaults survive would also pass against a wipe-and-recreate migration.
///
/// Every new column must read NULL after the upgrade, and `breastfeeding` is
/// the one worth stating out loud: it is a NULLABLE bool precisely so that
/// "never asked" stays distinct from "answered no". A non-null default would
/// answer a clinical question on behalf of every existing user, and the doctor
/// report would then print that invented answer.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not the migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v8 -> current adds the clinical columns and preserves existing data',
      () async {
    final schema = await verifier.schemaAt(8);

    final oldDb = DatabaseAtV8(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, weight_unit, '
      'last_synced_at, settings_updated_at, analysis_consent_uid, '
      'date_of_birth, height_cm, profile_weight_kg, menarche_age) '
      'VALUES (0, 33, 6, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'lb',
        DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 8, 2).millisecondsSinceEpoch ~/ 1000,
        'uid-abc',
        DateTime(1994, 3, 17).millisecondsSinceEpoch ~/ 1000,
        166.5,
        58.2,
        13,
      ],
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms, notes) VALUES (?, ?, ?)',
      [
        DateTime(2026, 3, 3).millisecondsSinceEpoch ~/ 1000,
        '{"cramps":true,"lbd_low":true,"slf_masturbation":true}',
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
    await verifier.migrateAndValidate(db, 10);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 33);
    expect(settings.defaultPeriodLength, 6);
    expect(settings.weightUnit, 'lb'); // v4 data untouched
    expect(settings.lastSyncedAt, DateTime(2026, 8, 1)); // v5 data untouched
    expect(settings.analysisConsentUid, 'uid-abc'); // v7 data untouched
    // v8's profile answers are the ones most at risk here: they are the newest
    // columns and therefore the ones a careless rewrite would drop.
    expect(settings.dateOfBirth, DateTime(1994, 3, 17));
    expect(settings.heightCm, 166.5);
    expect(settings.profileWeightKg, 58.2);
    expect(settings.menarcheAge, 13);

    // The new columns exist and read as "never answered".
    expect(settings.contraceptionMethod, isNull);
    expect(settings.contraceptionStartDate, isNull);
    expect(settings.knownDiagnoses, isNull);
    expect(settings.breastfeeding, isNull,
        reason: 'never asked must stay distinct from answered no');
    expect(settings.breastfeedingSince, isNull);

    // The day-tags blob survived verbatim, intimate keys included. Those ride
    // `DailyLogs.symptoms` and need no migration of their own — which is only
    // true for as long as nothing rewrites the blob on upgrade.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms,
        '{"cramps":true,"lbd_low":true,"slf_masturbation":true}');
    expect(logs.single.notes, 'a note that must survive');

    // The unpushed deletion intent survived. Losing it resurrects the day.
    final tombstones = await db.select(db.syncTombstones).get();
    expect(tombstones, hasLength(1));
    expect(tombstones.single.date, DateTime(2026, 2, 2));

    await db.close();
  });
}
