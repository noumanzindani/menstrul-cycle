import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v12.dart';

/// v12 → v13 adds `cycleRegularity` to `AppSettings` without disturbing a row.
///
/// The column answers a question the wizard never used to ask: how much the
/// user's cycle varies. It matters only in the first two or three months —
/// `_stdDev` needs two COMPLETE cycles, and until then the ± window sat on its
/// `max(1, ...)` floor for everyone alike.
///
/// Seeds NON-DEFAULT values on purpose: asserting that defaults survive would
/// also pass against a wipe-and-recreate migration.
///
/// Validates against the CURRENT schema, like every other migration test here.
/// Getting there needed a fix first: `app_settings.theme_mode` had its
/// declared default moved to `'light'` while every database created earlier
/// physically carries `DEFAULT 'system'`, which SQLite cannot alter. That
/// divergence was invisible only because the tests all validated at 12 --
/// the next version bump, this one, would have broken all ten. `onCreate` now
/// seeds `themeMode` explicitly like the other two seed sites, so the declared
/// default went back to the frozen value and decides nothing.
///
/// The explicit `PRAGMA table_info` check is kept alongside it deliberately:
/// `cycleRegularity` is NULLABLE, so a missing `addColumn` branch does NOT
/// throw "no such column" on read -- it maps quietly to null, and every data
/// assertion below would still pass.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v12 -> v13 adds cycleRegularity, preserving the settings row',
      () async {
    final schema = await verifier.schemaAt(12);

    final oldDb = DatabaseAtV12(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, '
      ' sexual_health_baseline, menarche_age) '
      'VALUES (0, 31, 7, ?, 13)',
      ['{"sexFrequency":"freq_weekly"}'],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 14);
    final settings = await db.getSettings();

    final columns = await db
        .customSelect('PRAGMA table_info(app_settings)')
        .map((r) => r.read<String>('name'))
        .get();
    expect(columns, contains('cycle_regularity'));
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.menarcheAge, 13);
    expect(settings.sexualHealthBaseline, '{"sexFrequency":"freq_weekly"}');
    expect(settings.cycleRegularity, isNull,
        reason: 'the migration is additive and backfills nothing; a user who '
            'upgraded was never asked, and null is the only honest answer — '
            'defaulting it to "regular" would invent a claim she never made');

    // Usable post-migration, not merely present.
    await db.update(db.appSettings).write(
          const AppSettingsCompanion(
            cycleRegularity: Value(kRegularityIrregular),
          ),
        );
    final after = await db.getSettings();
    expect(after.cycleRegularity, kRegularityIrregular);
    expect(after.defaultCycleLength, 31,
        reason: 'writing the new column rewrote an old one');

    await db.close();
  });
}
