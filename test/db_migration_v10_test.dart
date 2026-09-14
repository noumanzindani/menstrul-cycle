import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v9.dart';

/// v9 → v10 must ADD the signup sexual-health baseline column without
/// disturbing existing rows. Seeds NON-DEFAULT values on purpose: asserting
/// defaults survive would also pass against a wipe-and-recreate migration.
///
/// The new column must read NULL. That is the only correct answer — an existing
/// user was never taken through the new wizard pages, and a fabricated
/// frequency would reach the doctor report as something they said.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v9 -> v10 adds the baseline column and preserves existing data',
      () async {
    final schema = await verifier.schemaAt(9);

    final oldDb = DatabaseAtV9(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, weight_unit, '
      'date_of_birth, height_cm, menarche_age, contraception_method, '
      'known_diagnoses, breastfeeding) '
      'VALUES (0, 30, 4, ?, ?, ?, ?, ?, ?, ?)',
      [
        'lb',
        DateTime(1994, 3, 17).millisecondsSinceEpoch ~/ 1000,
        166.5,
        13,
        'contra_combined_pill',
        '["dx_pcos"]',
        1,
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
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 11);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 30);
    expect(settings.weightUnit, 'lb');
    // v8 and v9 answers are the ones most at risk: newest columns, likeliest
    // to be dropped by a careless rewrite.
    expect(settings.dateOfBirth, DateTime(1994, 3, 17));
    expect(settings.heightCm, 166.5);
    expect(settings.menarcheAge, 13);
    expect(settings.contraceptionMethod, 'contra_combined_pill');
    expect(settings.knownDiagnoses, '["dx_pcos"]');
    expect(settings.breastfeeding, isTrue);

    expect(settings.sexualHealthBaseline, isNull,
        reason: 'an existing user never saw the new wizard pages');

    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms,
        '{"cramps":true,"lbd_low":true,"slf_masturbation":true}');
    expect(logs.single.notes, 'a note that must survive');

    await db.close();
  });
}
