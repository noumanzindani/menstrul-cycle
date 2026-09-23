import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v13.dart';

/// v13 → v14 adds `pregnancyStatus` and `pregnancyStatusDate` to
/// `AppSettings` without disturbing a row.
///
/// Seeds NON-DEFAULT values on purpose: asserting that defaults survive would
/// also pass against a wipe-and-recreate migration. The `PRAGMA table_info`
/// check stays alongside because both columns are NULLABLE, so a missing
/// `addColumn` branch would map quietly to null rather than throw.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v13 -> v14 adds the pregnancy columns, preserving the settings row',
      () async {
    final schema = await verifier.schemaAt(13);

    final oldDb = DatabaseAtV13(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, '
      ' cycle_regularity, menarche_age) '
      'VALUES (0, 31, 7, ?, 13)',
      [kRegularityIrregular],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 15);
    final settings = await db.getSettings();

    final columns = await db
        .customSelect('PRAGMA table_info(app_settings)')
        .map((r) => r.read<String>('name'))
        .get();
    expect(columns, containsAll(['pregnancy_status', 'pregnancy_status_date']));
    expect(settings.defaultCycleLength, 31);
    expect(settings.menarcheAge, 13);
    expect(settings.cycleRegularity, kRegularityIrregular);
    expect(settings.pregnancyStatus, isNull,
        reason: 'an upgrading user was never asked; "no" would be invented');
    expect(settings.pregnancyStatusDate, isNull);

    // Usable post-migration, not merely present.
    final when = DateTime(2026, 8, 10);
    await db.update(db.appSettings).write(
          AppSettingsCompanion(
            pregnancyStatus: const Value(kPregnancyBirth),
            pregnancyStatusDate: Value(when),
          ),
        );
    final after = await db.getSettings();
    expect(after.pregnancyStatus, kPregnancyBirth);
    expect(after.pregnancyStatusDate, when);
    expect(after.defaultCycleLength, 31,
        reason: 'writing the new columns rewrote an old one');

    await db.close();
  });
}
