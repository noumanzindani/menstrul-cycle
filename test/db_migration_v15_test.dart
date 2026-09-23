import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v14.dart';

/// v14 → v15 adds the four puberty columns to `AppSettings` without
/// disturbing a row. Seeds NON-DEFAULT values so a wipe-and-recreate
/// migration would fail, and checks `PRAGMA table_info` because every new
/// column is nullable and a missing `addColumn` would read quietly as null.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v14 -> v15 adds the puberty columns, preserving the settings row',
      () async {
    final schema = await verifier.schemaAt(14);

    final oldDb = DatabaseAtV14(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, '
      ' pregnancy_status, menarche_age) '
      'VALUES (0, 31, 7, ?, 13)',
      [kPregnancyNone],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 15);
    final settings = await db.getSettings();

    final columns = await db
        .customSelect('PRAGMA table_info(app_settings)')
        .map((r) => r.read<String>('name'))
        .get();
    expect(
        columns,
        containsAll([
          'breast_stage',
          'pubic_hair_stage',
          'puberty_timing',
          'puberty_answered_on',
        ]));
    expect(settings.defaultCycleLength, 31);
    expect(settings.pregnancyStatus, kPregnancyNone);
    expect(settings.breastStage, isNull,
        reason: 'an upgrading user was never asked');
    expect(settings.pubicHairStage, isNull);
    expect(settings.pubertyTiming, isNull);
    expect(settings.pubertyAnsweredOn, isNull);

    final when = DateTime(2026, 9, 1);
    await db.update(db.appSettings).write(
          AppSettingsCompanion(
            breastStage: const Value('tan_b3'),
            pubicHairStage: const Value('tan_p2'),
            pubertyTiming: const Value('pub_early'),
            pubertyAnsweredOn: Value(when),
          ),
        );
    final after = await db.getSettings();
    expect(after.breastStage, 'tan_b3');
    expect(after.pubicHairStage, 'tan_p2');
    expect(after.pubertyTiming, 'pub_early');
    expect(after.pubertyAnsweredOn, when);
    expect(after.menarcheAge, 13,
        reason: 'writing the new columns rewrote an old one');

    await db.close();
  });
}
