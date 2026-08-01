import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v3.dart';

/// The v3→v4 upgrade must ADD weightUnit without disturbing existing rows.
/// Seeds NON-DEFAULT values on purpose: asserting that defaults survive would
/// also pass against a wipe-and-recreate migration.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not a migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v3 -> v4 adds weightUnit and preserves existing data', () async {
    final schema = await verifier.schemaAt(3);

    final oldDb = DatabaseAtV3(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, premium, '
      'tracking_categories) '
      "VALUES (0, 31, 7, 1, '[\"physical_symptoms\",\"urine\"]')",
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms) VALUES (?, ?)',
      [
        DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
        '{"cramps":true,"weight":62.5}',
      ],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.premium, isTrue);
    expect(settings.trackingCategories, contains('urine'));
    expect(settings.weightUnit, isNull); // null => kg

    // A weight logged before the upgrade survives, because weight lives in the
    // day-tags blob and this migration never touches daily_logs.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(decodeNumber(logs.single.symptoms, kMetricWeight), 62.5);

    await db.close();
  });
}
