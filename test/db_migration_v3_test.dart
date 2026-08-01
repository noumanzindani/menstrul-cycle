import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v2.dart';

/// The upgrade from v2 must ADD every intervening column without disturbing
/// existing rows. Seeds NON-DEFAULT values on purpose: asserting that defaults
/// survive would also pass against a wipe-and-recreate migration.
///
/// This validates against the CURRENT schema, not v3: `migrateAndValidate`
/// upgrades the real `AppDatabase` to its own `schemaVersion`, so once that
/// moved past 3 this test could no longer stop there. That makes it the
/// MULTI-HOP guard — it proves a v2-era user runs `from < 3` AND `from < 4`,
/// which is the whole reason the branches are independent `if`s and not
/// `else if`s. Keep re-pointing it at the newest version on every bump.
///
/// An in-memory `AppDatabase.forTesting(NativeDatabase.memory())` test cannot
/// replace this — it runs `onCreate`/`createAll()` against the CURRENT schema
/// and never executes `onUpgrade`, so it passes whether or not a migration
/// exists. Only `SchemaVerifier` actually starts at v2 and upgrades.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v2 -> v4 adds every intervening column and preserves existing data',
      () async {
    // schemaAt() hands out multiple connections over ONE underlying database,
    // so rows seeded through the v2 database class are still there when the
    // real AppDatabase opens and upgrades. Seeding must go through a
    // GeneratedDatabase — a bare connection's executor is never opened.
    final schema = await verifier.schemaAt(2);

    final oldDb = DatabaseAtV2(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, premium) '
      'VALUES (0, 31, 7, 1)',
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms) VALUES (?, ?)',
      [DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000, '{"cramps":true}'],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.premium, isTrue);
    expect(settings.trackingCategories, isNull); // null => use defaults
    // Proves the `from < 4` branch also ran on this v2-era hop.
    expect(settings.weightUnit, isNull); // null => kg

    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, contains('cramps'));

    await db.close();
  });
}
