import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v2.dart';

/// The v2→v3 upgrade must ADD the column without disturbing existing rows.
/// Seeds NON-DEFAULT values on purpose: asserting that defaults survive would
/// also pass against a wipe-and-recreate migration.
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

  test('v2 -> v3 adds trackingCategories and preserves existing data',
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
    await verifier.migrateAndValidate(db, 3);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.premium, isTrue);
    expect(settings.trackingCategories, isNull); // null => use defaults

    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, contains('cramps'));

    await db.close();
  });
}
